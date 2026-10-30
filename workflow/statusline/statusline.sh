#!/bin/bash
# Statusline: badge do caveman + linhas de uso (modelo, tokscale e limites do plano).
input=$(cat)
dir=$(dirname "$0")

caveman=$(printf '%s' "$input" | bash "$dir/../hooks/caveman-statusline.sh" 2>/dev/null)

# Teste A/B: `touch ~/.cache/claude-statusline/off` esconde as linhas extras.
if [ -f "$HOME/.cache/claude-statusline/off" ]; then
  [ -n "$caveman" ] && printf '%s\n' "$caveman"
  exit 0
fi

# A 1ª linha (modelo/agentes) vai ao lado do badge, para não gastar uma linha a mais.
mapfile -t lines < <(printf '%s' "$input" | python3 "$dir/usage.py")
printf '%s\n' "${caveman:+$caveman  }${lines[0]}" "${lines[@]:1}"
