import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// People root: server-side person search on one segment, cohorts on the other.
public struct PeopleView: View {
  enum Segment: String, CaseIterable {
    case persons = "Persons"
    case cohorts = "Cohorts"
  }

  @State private var segment: Segment = .persons
  @State private var personsModel: PersonsListModel
  @State private var cohortsModel: CohortsListModel

  private let onOpenPerson: (String) -> Void

  public init(context: ProjectContext, onOpenPerson: @escaping (String) -> Void) {
    self._personsModel = State(initialValue: PersonsListModel(context: context))
    self._cohortsModel = State(initialValue: CohortsListModel(context: context))
    self.onOpenPerson = onOpenPerson
  }

  public var body: some View {
    VStack(spacing: 0) {
      Picker("Section", selection: $segment) {
        ForEach(Segment.allCases, id: \.self) { segment in
          Text(segment.rawValue).tag(segment)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, PHSpacing.lg)
      .padding(.vertical, PHSpacing.sm)

      switch segment {
      case .persons: personsContent
      case .cohorts: cohortsContent
      }
    }
    .background(PHColor.background)
    .navigationTitle("People")
  }

  // MARK: Persons

  private var personsContent: some View {
    Group {
      switch personsModel.state {
      case .loading:
        skeletonList
      case .failed(let message):
        EmptyStateView(
          systemImage: "wifi.exclamationmark",
          title: "Couldn't load people",
          message: message,
          actionTitle: "Retry"
        ) {
          Task { await personsModel.load() }
        }
      case .loaded where personsModel.persons.isEmpty:
        EmptyStateView(
          systemImage: "person.2",
          title: "No people match",
          message: "People appear as your SDKs identify users."
        )
      case .loaded:
        List(personsModel.persons) { person in
          personRow(person)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await personsModel.load() }
      }
    }
    .searchable(text: $personsModel.search, prompt: "Search by email or ID")
    .task { await personsModel.load() }
    .task(id: personsModel.search) {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      await personsModel.load()
    }
  }

  private func personRow(_ person: Person) -> some View {
    Button {
      onOpenPerson(person.id)
    } label: {
      HStack(spacing: PHSpacing.md) {
        VStack(alignment: .leading, spacing: 2) {
          Text(person.displayName)
            .font(.body.weight(.semibold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          if let distinctID = person.distinctIDs.first {
            Text(distinctID)
              .font(PHFont.mono(12))
              .foregroundStyle(PHColor.textSecondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
        Spacer()
        if let created = person.createdAt {
          Text(RelativeDateFormat.ago(created))
            .font(.caption)
            .foregroundStyle(PHColor.textTertiary)
        }
        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(PHColor.textTertiary)
      }
      .frame(minHeight: 44)
    }
  }

  // MARK: Cohorts

  private var cohortsContent: some View {
    Group {
      switch cohortsModel.state {
      case .loading:
        skeletonList
      case .failed(let message):
        EmptyStateView(
          systemImage: "wifi.exclamationmark",
          title: "Couldn't load cohorts",
          message: message,
          actionTitle: "Retry"
        ) {
          Task { await cohortsModel.load() }
        }
      case .loaded where cohortsModel.cohorts.isEmpty:
        EmptyStateView(
          systemImage: "person.3",
          title: "No cohorts yet",
          message: "Cohorts you create show up here."
        )
      case .loaded:
        List(cohortsModel.cohorts) { cohort in
          cohortRow(cohort)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await cohortsModel.load() }
      }
    }
    .task { await cohortsModel.load() }
  }

  private func cohortRow(_ cohort: Cohort) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: PHSpacing.sm) {
        Text(cohort.name.isEmpty ? "Untitled cohort" : cohort.name)
          .font(.body.weight(.semibold))
          .foregroundStyle(PHColor.textPrimary)
          .lineLimit(1)
        if cohort.isStatic {
          Text("Static")
            .font(.caption2.weight(.bold))
            .foregroundStyle(PHColor.textSecondary)
            .padding(.horizontal, PHSpacing.sm)
            .padding(.vertical, 2)
            .background(PHColor.divider, in: Capsule())
        }
      }
      if let count = cohort.count {
        Text("\(MetricFormat.compact(count)) people")
          .font(.caption)
          .foregroundStyle(PHColor.textSecondary)
      }
    }
    .frame(minHeight: 44)
  }

  private var skeletonList: some View {
    List {
      ForEach(0..<8, id: \.self) { _ in
        SkeletonView(cornerRadius: 10).frame(height: 40).listRowBackground(Color.clear)
      }
    }
    .listStyle(.plain)
  }
}

@MainActor
@Observable
final class PersonsListModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var persons: [Person] = []
  var search = ""

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  func load() async {
    do {
      let page = try await context.client.persons(
        projectID: context.projectID,
        search: search.isEmpty ? nil : search
      )
      persons = page.results
      state = .loaded
    } catch {
      if persons.isEmpty {
        state = .failed("Check your connection and try again.")
      }
    }
  }
}

@MainActor
@Observable
final class CohortsListModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var cohorts: [Cohort] = []

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  func load() async {
    do {
      let page = try await context.client.cohorts(projectID: context.projectID)
      cohorts = page.results
      state = .loaded
    } catch {
      if cohorts.isEmpty {
        state = .failed("Check your connection and try again.")
      }
    }
  }
}
