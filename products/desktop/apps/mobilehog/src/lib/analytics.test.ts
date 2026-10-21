import { describe, expect, it } from "vitest";
import { scrubError, scrubProperties } from "./analyticsScrub";

describe("analytics scrubbing", () => {
  it("drops prompt, token, and body properties", () => {
    expect(
      scrubProperties({
        task_id: "t1",
        prompt: "secret prompt",
        token: "phx_secret",
        body: "response body",
        search: "find me",
        ok: true,
      }),
    ).toEqual({
      task_id: "t1",
      ok: true,
    });
  });

  it("keeps only the error name for exceptions", () => {
    const scrubbed = scrubError(new Error("contains a prompt and token"));
    expect(scrubbed).toBeInstanceOf(Error);
    expect(scrubbed.message).toBe("Error");
    expect(scrubbed.name).toBe("Error");
    expect(scrubbed.stack).toBeUndefined();
  });
});
