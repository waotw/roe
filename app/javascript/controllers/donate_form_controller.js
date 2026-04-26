import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="donate-form"
//
// On connect: hydrates each preset button label with the localized
// currency string (e.g. "$5", "€10", "¥500"). The HTML emits bare
// numbers so the wrong-currency symbol never flashes for non-USD
// sites before JS runs.
//
// On preset click: fills the visible amount input with the preset
// value formatted to the currency's natural decimal count
// (USD/EUR → "5.00", JPY → "5", BHD → "5.000"). Doesn't submit;
// the user reviews and presses the main Donate button.
export default class extends Controller {
  static targets = ["input", "preset"];
  static values = { currency: { type: String, default: "USD" } };

  connect() {
    this.presetTargets.forEach((btn) => {
      const amount = Number(btn.dataset.amount);
      if (Number.isNaN(amount)) return;
      btn.textContent = this.labelFormatter.format(amount);
    });
  }

  select(event) {
    const amount = Number(event.currentTarget.dataset.amount);
    if (Number.isNaN(amount)) return;

    if (this.hasInputTarget) {
      this.inputTarget.value = amount.toFixed(this.fractionDigits);
      this.inputTarget.focus();
    }

    this.presetTargets.forEach((btn) => {
      btn.classList.toggle("is-selected", btn === event.currentTarget);
    });
  }

  // Compact currency formatter used for button labels: "$5" / "€10"
  // (no decimals, since presets are whole-unit amounts).
  get labelFormatter() {
    if (this._labelFormatter) return this._labelFormatter;
    try {
      this._labelFormatter = new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: this.currencyValue.toUpperCase(),
        minimumFractionDigits: 0,
        maximumFractionDigits: 0,
      });
    } catch (e) {
      this._labelFormatter = new Intl.NumberFormat(undefined);
    }
    return this._labelFormatter;
  }

  // Decimal count for the input value when a preset is selected.
  // Cached on first access. Falls back to 2 decimals if the runtime's
  // Intl data doesn't recognize the currency code.
  get fractionDigits() {
    if (this._fractionDigits !== undefined) return this._fractionDigits;
    try {
      const fmt = new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: this.currencyValue.toUpperCase(),
      });
      this._fractionDigits = fmt.resolvedOptions().minimumFractionDigits;
    } catch (e) {
      this._fractionDigits = 2;
    }
    return this._fractionDigits;
  }
}
