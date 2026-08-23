import { Controller } from "@hotwired/stimulus";

// Defaults a new post's audience to match the podcast or release it's going
// into: paid container, paid post.
//
// The audience select is a plain two-option list defaulting to `everyone`,
// which was right before shows and releases carried an audience of their own.
// Now it means clicking past the field creates a public episode on a paid
// podcast — a mistake you'd notice only when someone got it free.
//
// Only a default. Touching the field yourself stops this adjusting it, so an
// intentional free opener on a paid show stays free.
export default class extends Controller {
  static targets = ["audience"];
  static values = { paidPodcasts: Array, paidReleases: Array };

  connect() {
    this.userPicked = false;

    // The container select lives in a per-type group that new-content shows
    // and hides, so listen on the form rather than binding to a field that
    // may not be the visible one.
    this.onChange = (event) => {
      const name = event.target?.name;
      if (name === "fields[podcast]" || name === "fields[release]") this.apply();
      if (event.target?.id === "post_type") this.apply();
    };
    this.element.addEventListener("change", this.onChange);

    this.apply();
  }

  disconnect() {
    this.element.removeEventListener("change", this.onChange);
  }

  // Once it's been set deliberately, leave it alone for the rest of the form.
  userChose() {
    this.userPicked = true;
  }

  apply() {
    if (this.userPicked || !this.hasAudienceTarget) return;

    this.audienceTarget.value = this.inPaidContainer() ? "paid" : "everyone";
  }

  // Only fields that are actually in play — new-content disables the groups
  // for unselected post types, and a disabled field's value isn't the answer.
  inPaidContainer() {
    return (
      this.selected("fields[podcast]", this.paidPodcastsValue) ||
      this.selected("fields[release]", this.paidReleasesValue)
    );
  }

  selected(name, paidKeys) {
    if (!paidKeys?.length) return false;

    return Array.from(this.element.querySelectorAll(`[name="${name}"]`)).some(
      (field) => !field.disabled && paidKeys.includes(field.value.trim()),
    );
  }
}
