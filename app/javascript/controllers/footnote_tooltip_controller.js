import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.tooltip = this.createTooltip();
    this.setupFootnoteLinks();
    this.hideTimeout = null;
  }

  disconnect() {
    this.tooltip?.remove();
    if (this.hideTimeout) clearTimeout(this.hideTimeout);
  }

  createTooltip() {
    const tooltip = document.createElement("div");
    tooltip.className = "footnote-tooltip";
    tooltip.style.position = "absolute";
    tooltip.style.display = "none";
    tooltip.style.pointerEvents = "auto"; // Explicitly enable pointer events

    tooltip.addEventListener("mouseenter", () => this.cancelHide());
    tooltip.addEventListener("mouseleave", () => this.scheduleHide());

    document.body.appendChild(tooltip);
    return tooltip;
  }

  setupFootnoteLinks() {
    const footnoteLinks = this.element.querySelectorAll(
      'a.footnote[href^="#fn:"]',
    );

    footnoteLinks.forEach((link) => {
      link.addEventListener("mouseenter", (e) => this.showTooltip(e));
      link.addEventListener("mouseleave", () => this.scheduleHide());
    });
  }

  showTooltip(event) {
    this.cancelHide();

    const link = event.currentTarget;
    const footnoteId = link.getAttribute("href").substring(1);
    const footnoteElement = document.getElementById(footnoteId);

    if (!footnoteElement) return;

    const footnoteText = this.extractFootnoteText(footnoteElement);

    this.tooltip.innerHTML = footnoteText;
    this.tooltip.style.display = "block";
    this.positionTooltip(link);
  }

  scheduleHide() {
    this.hideTimeout = setTimeout(() => this.hideTooltip(), 300);
  }

  cancelHide() {
    if (this.hideTimeout) {
      clearTimeout(this.hideTimeout);
      this.hideTimeout = null;
    }
  }

  hideTooltip() {
    this.tooltip.style.display = "none";
  }

  positionTooltip(link) {
    const linkRect = link.getBoundingClientRect();
    const margin = 5;
    const edgeMargin = 34;

    // Position below link
    let x = linkRect.left + window.scrollX + margin;
    let y = linkRect.bottom + window.scrollY + margin;

    // Get tooltip dimensions (only once, after content is set)
    const tooltipRect = this.tooltip.getBoundingClientRect();

    // Check right edge
    const wouldOverflowRight =
      linkRect.left + tooltipRect.width > window.innerWidth - edgeMargin;
    if (wouldOverflowRight) {
      x = window.innerWidth - tooltipRect.width - edgeMargin + window.scrollX;
    }

    // Check bottom edge
    const wouldOverflowBottom =
      linkRect.bottom + tooltipRect.height > window.innerHeight - edgeMargin;
    if (wouldOverflowBottom) {
      y = linkRect.top + window.scrollY - tooltipRect.height - margin;
    }

    this.tooltip.style.left = `${Math.max(window.scrollX + edgeMargin, x)}px`;
    this.tooltip.style.top = `${y}px`;
  }

  extractFootnoteText(footnoteElement) {
    const clone = footnoteElement.cloneNode(true);
    const backref = clone.querySelector('a[href^="#fnref:"]');
    if (backref) backref.remove();
    return clone.innerHTML.trim();
  }
}
