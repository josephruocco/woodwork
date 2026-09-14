# Calibre adoption plan

## Positioning

**WoodWork turns a Calibre library—or any Virtual Library—into a rotating
visual shortlist, then puts that shelf on the iPhone Home Screen.**

Do not market WoodWork as another ebook reader, another Calibre bookshelf, or a
way to pick one random book. Calibre already does those jobs. The useful loop is:

1. Filter a collection in Calibre, such as unread fiction.
2. Use the free plugin to reshuffle it into a manageable shortlist.
3. Connect the iPhone app to the same Content Server.
4. Keep rediscovering the collection through the hourly Home Screen widget.

## Release sequence

### 1. Private compatibility check

- Verify the plugin on Calibre 7, 8, and 9.
- Verify macOS, Windows, and Linux before asking for Plugin Index inclusion.
- Test an empty view, a normal search, a saved search, and a Virtual Library.
- Confirm repeatedly reshuffling does not shrink the original candidate pool.
- Confirm Restore Previous View returns to the exact prior search.
- Confirm no metadata or files change.
- Test iPhone discovery, manual addresses, authentication, multiple libraries,
  and a Content Server using a URL prefix.

The package has been installed successfully on Calibre 9.2.1 and the iOS client
has been checked against a live Calibre 9.2.1 Content Server. Calibre 7/8 and
Windows/Linux remain explicit beta test targets, not verified claims.

### 2. MobileRead beta

- Publish the prepared post in the **Calibre Plugins** forum.
- Attach exactly one `WoodWorkShelf.zip` to the first post.
- Label it beta and ask testers to include OS, Calibre version, and the steps
  that failed when reporting a problem.
- Answer every substantive report and publish small, numbered releases.
- After compatibility is established, ask a forum moderator to add it to the
  Plugin Index so Calibre's Plugin Updater can surface it.

### 3. iPhone conversion

- Link to the iPhone app only in the plugin's About/help area and forum post.
- Do not add pop-ups, recurring prompts, analytics, or toolbar advertising.
- Give the plugin complete standalone value; the iPhone widget is the optional
  continuation, not a requirement.
- Send users to `getwoodwork.app/calibre/`, where the plugin download and
  iPhone connection instructions appear together.

### 4. Broader launch

After the first ten successful external installs:

- Post a short demonstration to r/Calibre and relevant ebook communities.
- Ask MobileRead moderators whether the plugin is suitable for a mention in a
  future Calibre release post.
- Publish one honest comparison: Calibre's built-in random-book command chooses
  one title; WoodWork makes a browsable rotating shortlist and carries it to a
  Home Screen widget.
- Approach Hacker News only after the App Store listing is live. Lead with the
  page-count-driven visualization and local-first Calibre bridge, not a generic
  app announcement.

## Four-week operating plan

| Week | Work | Exit condition |
|---|---|---|
| 1 | Recruit 5 cross-platform testers | No data-loss or restore bugs |
| 2 | MobileRead beta and rapid fixes | 10 successful installs |
| 3 | Plugin Index request and Calibre landing page | Download/update path works |
| 4 | Reddit demonstration and iOS cross-promotion | 10 successful iOS connections |

## Metrics that matter

- Successful plugin installs by OS and Calibre major version.
- Percentage of iPhone users who complete a Calibre connection.
- Plugin-download-to-iPhone-install conversion.
- Weekly users who open WoodWork from the widget.
- Connection failures grouped by discovery, address, authentication, or server
  version.

Initial targets: **20 plugin installs, 10 connected iPhones, and 5 users still
using the widget after one week.** Larger download counts are noise until those
three numbers exist.

## Trust rules

- Keep the plugin source visible and the ZIP reproducible from the repository.
- No telemetry in the plugin.
- Never modify Calibre metadata or book files.
- Recommend same-Wi-Fi use. Do not instruct ordinary users to expose port 8080
  to the internet; remote access requires authentication and HTTPS.
- State clearly that the iPhone app copies metadata for its widget, not ebook
  files.

## Community references

- [Calibre Interface Action plugin documentation](https://manual.calibre-ebook.com/creating_plugins.html)
- [Calibre Content Server documentation](https://manual.calibre-ebook.com/server.html)
- [MobileRead plugin forum](https://www.mobileread.com/forums/forumdisplay.php?f=237)
- [MobileRead Plugin Index instructions](https://www.mobileread.com/forums/showthread.php?t=118764)

