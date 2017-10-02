#!/bin/zsh
#     ____      ____
#    / __/___  / __/
#   / /_/_  / / /_
#  / __/ / /_/ __/
# /_/   /___/_/-completion.zsh
#
# - $FZF_TMUX               (default: 0)
# - $FZF_TMUX_HEIGHT        (default: '40%')
# - $FZF_COMPLETION_TRIGGER (default: '**')
# - $FZF_COMPLETION_OPTS    (default: empty)

# To use custom commands instead of find, override _fzf_compgen_{path,dir}
if ! declare -f _fzf_compgen_path > /dev/null; then
  _fzf_compgen_path() {
    command find -L "$1" \
      -name .git -prune -o -name .svn -prune -o \( -type d -o -type f -o -type l \) \
      -a -not -path "$1" -print 2> /dev/null | sed 's@^\./@@'
  }
fi

if ! declare -f _fzf_compgen_dir > /dev/null; then
  _fzf_compgen_dir() {
    command find -L "$1" \
      -name .git -prune -o -name .svn -prune -o -type d \
      -a -not -path "$1" -print 2> /dev/null | sed 's@^\./@@'
  }
fi

if ! declare -f _fzf_compgen_fasd_path > /dev/null; then
  _fzf_compgen_fasd_path() {
    command fasd -Ral | sed "s%^${PWD}/%%"
  }
fi

if ! declare -f _fzf_compgen_fasd_file > /dev/null; then
  _fzf_compgen_fasd_file() {
    command fasd -Rfl | sed "s%^${PWD}/%%"
  }
fi

if ! declare -f _fzf_compgen_fasd_dir > /dev/null; then
  _fzf_compgen_fasd_dir() {
    command fasd -Rdl | sed "s%^${PWD}/%%"
  }
fi

###########################################################

__fzfcmd_complete() {
  [ -n "$TMUX_PANE" ] && [ "${FZF_TMUX:-0}" != 0 ] && [ ${LINES:-40} -gt 15 ] &&
    echo "fzf-tmux -d${FZF_TMUX_HEIGHT:-40%}" || echo "fzf"
}

__fzf_generic_path_completion() {
  local base lbuf compgen fzf_opts suffix tail fzf dir leftover matches
  # (Q) flag removes a quoting level: "foo\ bar" => "foo bar"
  base=${(Q)1}
  lbuf=$2
  compgen=$3
  fzf_opts=$4
  suffix=$5
  tail=$6
  fzf="$(__fzfcmd_complete)"

  setopt localoptions nonomatch
  dir="$base"
  while [ 1 ]; do
    if [[ -z "$dir" || -d ${~dir} ]]; then
      leftover=${base/#"$dir"}
      leftover=${leftover/#\/}
      [ -z "$dir" ] && dir='.'
      [ "$dir" != "/" ] && dir="${dir/%\//}"
      dir=${~dir}
      matches=$(eval "$compgen $(printf %q "$dir")" | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" ${=fzf} ${=fzf_opts} -q "$leftover" | while read item; do
        echo -n "${(q)item}$suffix "
      done)
      matches=${matches% }
      if [ -n "$matches" ]; then
        LBUFFER="$lbuf$matches$tail"
      fi
      zle redisplay
      typeset -f zle-line-init >/dev/null && zle zle-line-init
      break
    fi
    dir=$(dirname "$dir")
    dir=${dir%/}/
  done
}

_fzf_path_completion() {
  __fzf_generic_path_completion "$1" "$2" _fzf_compgen_path \
    "-m" "" " "
}

_fzf_dir_completion() {
  __fzf_generic_path_completion "$1" "$2" _fzf_compgen_dir \
    "" "/" ""
}

_fzf_fasd_path_completion() {
  __fzf_generic_path_completion "$1" "$2" _fzf_compgen_fasd_path \
    "-m --tiebreak=end,index" "" " "
}

_fzf_fasd_file_completion() {
  __fzf_generic_path_completion "$1" "$2" _fzf_compgen_fasd_file \
    "-m --tiebreak=end,index" "" " "
}

_fzf_fasd_dir_completion() {
  __fzf_generic_path_completion "$1" "$2" _fzf_compgen_fasd_dir \
    "--tiebreak=end,index" "/" ""
}

_fzf_feed_fifo() (
  command rm -f "$1"
  mkfifo "$1"
  cat <&0 > "$1" &
)

_fzf_complete() {
  local fifo fzf_opts lbuf fzf matches post
  fifo="${TMPDIR:-/tmp}/fzf-complete-fifo-$$"
  fzf_opts=$1
  lbuf=$2
  post="${funcstack[2]}_post"
  type $post > /dev/null 2>&1 || post=cat

  fzf="$(__fzfcmd_complete)"

  _fzf_feed_fifo "$fifo"
  matches=$(cat "$fifo" | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" ${=fzf} ${=fzf_opts} -q "${(Q)prefix}" | $post | tr '\n' ' ')
  if [ -n "$matches" ]; then
    LBUFFER="$lbuf$matches"
  fi
  zle redisplay
  typeset -f zle-line-init >/dev/null && zle zle-line-init
  command rm -f "$fifo"
}

_fzf_complete_telnet() {
  _fzf_complete '+m' "$@" < <(
    command grep -v '^\s*\(#\|$\)' /etc/hosts | command grep -Fv '0.0.0.0' |
        awk '{if (length($2) > 0) {print $2}}' | sort -u
  )
}

_fzf_complete_ssh() {
  _fzf_complete '+m' "$@" < <(
    command cat <(cat ~/.ssh/config /etc/ssh/ssh_config 2> /dev/null | command grep -i '^host' | command grep -v '*' | awk '{for (i = 2; i <= NF; i++) print $1 " " $i}') \
        <(command grep -oE '^[a-z0-9.,:-]+' ~/.ssh/known_hosts | tr ',' '\n' | awk '{ print $1 " " $1 }') \
        <(command grep -v '^\s*\(#\|$\)' /etc/hosts | command grep -Fv '0.0.0.0') |
        awk '{if (length($2) > 0) {print $2}}' | sort -u
  )
}

_fzf_complete_export() {
  _fzf_complete '-m' "$@" < <(
    declare -xp | sed 's/=.*//' | sed 's/.* //'
  )
}

_fzf_complete_unset() {
  _fzf_complete '-m' "$@" < <(
    declare -xp | sed 's/=.*//' | sed 's/.* //'
  )
}

_fzf_complete_unalias() {
  _fzf_complete '+m' "$@" < <(
    alias | sed 's/=.*//'
  )
}

fzf-completion() {
  local tokens cmd prefix trigger_general trigger_fasd_paths trigger_fasd_files trigger_fasd_dirs triggers current_trigger tail reversed_head fzf matches lbuf d_cmds
  setopt localoptions noshwordsplit noksh_arrays noposixbuiltins

  # http://zsh.sourceforge.net/FAQ/zshfaq03.html
  # http://zsh.sourceforge.net/Doc/Release/Expansion.html#Parameter-Expansion-Flags
  tokens=(${(z)LBUFFER})
  if [ ${#tokens} -lt 1 ]; then
    zle ${fzf_default_completion:-expand-or-complete}
    return
  fi

  cmd=${tokens[1]}

  # Explicitly allow for empty trigger.
  # Important: all triggers must have the same character length!
  trigger_general=${FZF_COMPLETION_TRIGGER-'**'}
  trigger_fasd_paths=${FZF_COMPLETION_FASD_PATHS_TRIGGER-',,'}
  trigger_fasd_files=${FZF_COMPLETION_FASD_FILES_TRIGGER-',f'}
  trigger_fasd_dirs=${FZF_COMPLETION_FASD_DIRS_TRIGGER-',d'}
  triggers=($trigger_general $trigger_fasd_paths $trigger_fasd_files $trigger_fasd_dirs)
  [ -z "$trigger_general" -a ${LBUFFER[-1]} = ' ' ] && tokens+=("")

  tail=${LBUFFER:$(( ${#LBUFFER} - ${#trigger_general} ))}
  reversed_head=$(echo ${tokens[-1]:0:${#trigger_general}} | rev)

  # Kill completion (do not require trigger sequence)
  if [ $cmd = kill -a ${LBUFFER[-1]} = ' ' ]; then
    fzf="$(__fzfcmd_complete)"
    matches=$(ps -ef | sed 1d | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-50%} --min-height 15 --reverse $FZF_DEFAULT_OPTS --preview 'echo {}' --preview-window down:3:wrap $FZF_COMPLETION_OPTS" ${=fzf} -m | awk '{print $2}' | tr '\n' ' ')
    if [ -n "$matches" ]; then
      LBUFFER="$LBUFFER$matches"
    fi
    zle redisplay
    typeset -f zle-line-init >/dev/null && zle zle-line-init
  # Trigger sequence given
  elif [ ${#tokens} -gt 1 ] && ( (( ${triggers[(Ie)${tail}]} )) || (( ${triggers[(Ie)${reversed_head}]} )) ); then
    if (( ${triggers[(I)${tail}]} )); then
      current_trigger="$tail"
      prefix=${tokens[-1]:0:-${#current_trigger}}
    else
      current_trigger="$reversed_head"
      prefix=${tokens[-1]:${#current_trigger}}
    fi

    d_cmds=(${=FZF_COMPLETION_DIR_COMMANDS:-cd pushd rmdir})

    [ -z "${tokens[-1]}" ] && lbuf=$LBUFFER || lbuf=${LBUFFER:0:-${#tokens[-1]}}

    if [ "$current_trigger" = "$trigger_general" ]; then
      if eval "type _fzf_complete_${cmd} > /dev/null"; then
        eval "prefix=\"$prefix\" _fzf_complete_${cmd} \"$lbuf\""
      elif [ ${d_cmds[(i)$cmd]} -le ${#d_cmds} ]; then
        _fzf_dir_completion "$prefix" "$lbuf"
      else
        _fzf_path_completion "$prefix" "$lbuf"
      fi
    # fasd completion
    elif [ "$current_trigger" = "$trigger_fasd_paths" ]; then
      _fzf_fasd_path_completion "$prefix" "$lbuf"
    elif [ "$current_trigger" = "$trigger_fasd_files" ]; then
      _fzf_fasd_file_completion "$prefix" "$lbuf"
    else
      _fzf_fasd_dir_completion "$prefix" "$lbuf"
    fi
  # Fall back to default completion
  else
    zle ${fzf_default_completion:-expand-or-complete}
  fi
}

[ -z "$fzf_default_completion" ] && {
  binding=$(bindkey '^I')
  [[ $binding =~ 'undefined-key' ]] || fzf_default_completion=$binding[(s: :w)2]
  unset binding
}

zle     -N   fzf-completion
bindkey '^I' fzf-completion
