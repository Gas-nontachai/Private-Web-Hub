  const findSkipButtons = (selectors) => {
    const buttons = new Set(document.querySelectorAll(selectors));
    // Plain "skip" text is only safe inside an active ad player, not across arbitrary pages.
    const adControls = document.querySelectorAll(
      '.jwplayer.jw-flag-ads button,.jwplayer.jw-flag-ads [role="button"],#adgate button,#adgate [role="button"],[data-adgate] button,[data-adgate] [role="button"]'
    );
    for (const button of adControls) {
      if (button.matches('.jw-skip:not(.jw-skippable)')) continue;
      const label = (button.getAttribute('aria-label') || button.textContent || '').replace(/\s+/g, ' ').trim();
      if (/^(?:ข้าม(?:\s*โฆษณา)?|skip(?:\s+ads?)?)$/iu.test(label)) buttons.add(button);
    }
    return [...buttons];
  };
