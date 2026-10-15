import { Text } from "@components/text";
import { Pressable, ScrollView } from "react-native";

interface ChipRowProps<T extends string> {
  options: ReadonlyArray<{ value: T; label: string }>;
  value: T;
  onChange: (value: T) => void;
}

export function ChipRow<T extends string>({
  options,
  value,
  onChange,
}: ChipRowProps<T>) {
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={{ gap: 8, paddingHorizontal: 16 }}
    >
      {options.map((option) => {
        const active = option.value === value;
        return (
          <Pressable
            key={option.value}
            onPress={() => onChange(option.value)}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
            className={`rounded-full border px-3 py-1.5 ${active ? "border-accent-9 bg-accent-3" : "border-gray-5 bg-card active:bg-gray-2"}`}
          >
            <Text
              className={`font-medium text-[13px] ${active ? "text-accent-11" : "text-gray-11"}`}
            >
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}
