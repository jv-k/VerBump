#!/bin/bash

# shellcheck disable=SC2034

# Colour gate. Precedence:
#   1. NO_COLOR set (any value)            -> off   (https://no-color.org)
#   2. CLICOLOR_FORCE / FORCE_COLOR truthy -> on    (force colour without a TTY,
#                                                    e.g. piping into `less -R`,
#                                                    screenshot capture, or CI)
#   3. stdout is a TTY                      -> on
#   4. otherwise (pipe, file, CI)          -> off
if [ -n "${NO_COLOR:-}" ]; then
  USE_COLOR=0
elif { [ -n "${CLICOLOR_FORCE:-}" ] && [ "${CLICOLOR_FORCE}" != 0 ]; } \
  || { [ -n "${FORCE_COLOR:-}" ] && [ "${FORCE_COLOR}" != 0 ]; }; then
  USE_COLOR=1
elif [ -t 1 ]; then
  USE_COLOR=1
else
  USE_COLOR=0
fi

if [ "$USE_COLOR" = 1 ]; then
  # ANSI/VT100 colours
  YELLOW='\033[1;33m'
  LIGHTYELLOW='\033[0;33m'
  RED='\033[0;31m'
  LIGHTRED='\033[1;31m'
  GREEN='\033[0;32m'
  LIGHTGREEN='\033[1;32m'
  BLUE='\033[0;34m'
  LIGHTBLUE='\033[1;34m'
  PURPLE='\033[0;35m'
  LIGHTPURPLE='\033[1;35m'
  CYAN='\033[0;36m'
  LIGHTCYAN='\033[1;36m'
  WHITE='\033[1;37m'
  LIGHTGRAY='\033[0;37m'
  DARKGRAY='\033[1;30m'
  DIM='\033[2m'
  BOLD='\033[1m'
  INVERT='\033[7m'
  RESET='\033[0m'

  # The wordmark's diagonal gradient: WORDMARK_STOPS, two or more hex
  # colours that read on a dark background, blended in even segments: Monokai
  # Pro's yellow, green, cyan and purple, the theme of the pictures in img/.
  # dev/wordmark.js reads the same line to draw the README's pictures, so it
  # stays one hex list on one line.
  # WORDMARK_GRAD[k] is the 24-bit colour of a cell whose place on the
  # diagonal is k = x + WORDMARK_SHIFT * y, for the 21 x 3 cells of the
  # VerBump wordmark; usage() picks one per cell. Integer maths only, rounded
  # half up, so bash 3.2 needs no floating point.
  WORDMARK_STOPS=( ffd866 a9dc76 78dce8 ab9df2 )
  WORDMARK_SHIFT=2
  WORDMARK_GRAD=()
  _wm_stops=()
  for _wm_hex in "${WORDMARK_STOPS[@]}"; do
    _wm_stops+=( $(( 16#${_wm_hex:0:2} )) $(( 16#${_wm_hex:2:2} )) $(( 16#${_wm_hex:4:2} )) )
  done
  _wm_seg=$(( ${#WORDMARK_STOPS[@]} - 1 ))
  _wm_span=$(( 20 + WORDMARK_SHIFT * 2 ))
  _wm_k=0
  while (( _wm_k <= _wm_span )); do
    # at = seg * k / span; i is the segment, fnum / span the place within it.
    _wm_num=$(( _wm_k * _wm_seg ))
    _wm_i=$(( _wm_num / _wm_span )); (( _wm_i > _wm_seg - 1 )) && _wm_i=$(( _wm_seg - 1 ))
    _wm_f=$(( _wm_num - _wm_i * _wm_span ))
    _wm_rgb=()
    for _wm_c in 0 1 2; do
      _wm_from=${_wm_stops[_wm_i * 3 + _wm_c]}
      _wm_to=${_wm_stops[(_wm_i + 1) * 3 + _wm_c]}
      _wm_rgb+=( $(( (2 * (_wm_from * _wm_span + (_wm_to - _wm_from) * _wm_f) + _wm_span) / (2 * _wm_span) )) )
    done
    # Bash 3.2's printf -v takes a plain name only, not an array element.
    printf -v _wm_esc '\033[38;2;%d;%d;%dm' "${_wm_rgb[@]}"
    WORDMARK_GRAD[_wm_k]=$_wm_esc
    _wm_k=$(( _wm_k + 1 ))
  done
  unset _wm_stops _wm_hex _wm_seg _wm_span _wm_k _wm_num _wm_i _wm_f _wm_rgb _wm_c _wm_from _wm_to _wm_esc
  # shellcheck disable=SC2059
  WORDMARK_RST=$(printf "$RESET")
else
  YELLOW=''; LIGHTYELLOW=''; RED=''; LIGHTRED=''; GREEN=''; LIGHTGREEN=''
  BLUE=''; LIGHTBLUE=''; PURPLE=''; LIGHTPURPLE=''; CYAN=''; LIGHTCYAN=''
  WHITE=''; LIGHTGRAY=''; DARKGRAY=''; DIM=''; BOLD=''; INVERT=''; RESET=''
  WORDMARK_SHIFT=2; WORDMARK_GRAD=(); WORDMARK_RST=''
fi

# Preset styles (character-level) — semantic aliases. Call sites reference
# these rather than raw colour vars so a single edit here re-skins the tool.
S_NORM="${BOLD}"      # emphasis = bold of the terminal's own fg (no colour)
S_LIGHT="${DIM}"      # markers/secondary = dim the terminal fg (theme-adaptive)
S_WARN="${LIGHTRED}"
S_ERROR="${RED}"
S_DIM="${DIM}"
S_OK="${GREEN}"       # log_success    (✔ green)
S_INFO="${CYAN}"      # log_info       (ℹ cyan)
S_ATTN="${YELLOW}"    # log_warn       (! yellow)
S_BULLET="${PURPLE}"  # version_block  (• magenta bullets)
S_VAL="${GREEN}"      # inline values (versions, paths, remotes) in run output

# Deprecated — retained as an alias to $GREEN until the last call site migrates
# to a log_* helper. Tests forbid its use on narrative lines in lib/helpers.sh
# and verbump.sh (see test/ui.bats).
S_NOTICE="${GREEN}"

# Inverted-video bold pills for section headers — ` TEXT ` reads as a solid
# coloured bar. Five variants: cyan (primary), green (secondary), yellow
# (outdated / warning), red (error), magenta (interactive prompt — awaiting
# user input). Close with S_HDR_END.
#
# Built from a single combined ANSI sequence (7=invert, 1=bold, 3N=fg) rather
# than ${INVERT}${BOLD}${COLOUR} concatenated, because the standalone fg codes
# begin with "\033[0;" (reset) which cancels the preceding invert + bold.
if [ "$USE_COLOR" = 1 ]; then
  S_HDR_CYAN=$'\033[7;1;36m'
  S_HDR_SUB=$'\033[7;1;32m'
  S_HDR_YELLOW=$'\033[7;1;33m'
  S_HDR_RED=$'\033[7;1;31m'
  S_HDR_PURPLE=$'\033[7;1;35m'
  # Subdued pill for sub-headings nested inside a section (help opt-groups):
  # invert + faint + white fg — a mid-gray bar one level below the coloured
  # section pills. Faint-of-white (not bright-black) so the bar tracks the
  # theme's normal fg brightness; themes with a near-background brightBlack
  # would otherwise render it invisible.
  S_HDR_GRAY=$'\033[7;2;37m'
  S_HDR_END=$'\033[0m'
else
  S_HDR_CYAN=''; S_HDR_SUB=''; S_HDR_YELLOW=''; S_HDR_RED=''; S_HDR_PURPLE=''
  S_HDR_GRAY=''; S_HDR_END=''
fi
