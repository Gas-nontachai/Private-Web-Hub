  const isVisible = function(button) {
    if (!button.isConnected || button.hasAttribute("hidden") || button.disabled) {
      return false;
    }

    let element = button;
    while (element) {
      const style = window.getComputedStyle(element);
      if (
        style.display === "none" ||
        style.visibility === "hidden" ||
        style.visibility === "collapse" ||
        Number.parseFloat(style.opacity) <= 0
      ) {
        return false;
      }
      element = element.parentElement;
    }

    return button.getClientRects().length > 0;
  };
