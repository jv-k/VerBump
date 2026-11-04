# vhs tape — renders verbump --help as a single PNG (macOS-window look).
# Run with: vhs dev/help.tape   (or: npm run screenshots:help)
#
# vhs emits a full animated GIF for any tape — we don't use it here, so it
# lands in tmp/help.gif (gitignored). The single PNG we care about comes
# from the `Screenshot` directive at the bottom.

Output img/tmp/help.gif

Set Shell "zsh"
Set FontFamily "JetBrains Mono"
Set FontSize 15
Set Width 1000
# Tall enough to hold the whole --help — banner/logo through EXAMPLES — in one
# frame, and no taller. Three constraints: (1) vhs' Screenshot captures the
# viewport, so a short height scrolls the typed command + header logo off the
# top; (2) show-help pages through `less` when the help has more lines than the
# terminal has rows, so the height must also keep rows > lines or the
# screenshot catches the pager; (3) extra rows render as blank background at
# the bottom of the PNG, so don't overshoot — after editing the help text,
# re-render and trim/grow this until the frame is snug. This clears all three.
Set Height 2732
# Monokai Pro palette with a Carbon (#191816) background for the terminal itself.
Set Theme { "background": "#191816", "foreground": "#FCFCFA", "cursor": "#FCFCFA", "black": "#2D2A2E", "red": "#FF6188", "green": "#A9DC76", "yellow": "#FFD866", "blue": "#FC9867", "magenta": "#AB9DF2", "cyan": "#78DCE8", "white": "#FCFCFA", "brightBlack": "#727072", "brightRed": "#FF6188", "brightGreen": "#A9DC76", "brightYellow": "#FFD866", "brightBlue": "#FC9867", "brightMagenta": "#AB9DF2", "brightCyan": "#78DCE8", "brightWhite": "#FCFCFA", "selection": "#5B595C" }
Set Padding 12
Set Margin 8
Set MarginFill ""
Set BorderRadius 10
Set WindowBar Colorful
Set WindowBarSize 40
Set TypingSpeed 40ms

Hide
# Define `verbump` so the screenshot shows the installed-command form,
# not the in-repo `./verbump.sh` path. Clear AFTER defining it so the
# function line doesn't linger on screen when we Show.
Type 'verbump() { ./verbump.sh "$@"; }' Enter
Type "clear" Enter
Show

Type "verbump --help"
Sleep 400ms
Enter
Sleep 2s

Screenshot img/screenshot.png
