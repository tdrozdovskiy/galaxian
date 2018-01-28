#!/bin/bash
#==============================================================================
#
# FILE: galaxian.sh
#
# USAGE: galaxian.sh
#
# DESCRIPTION: Galaxian game for bash.
#
# OPTIONS: see function ’usage’ below
# REQUIREMENTS: Script was created on ubuntu 14.04 and bash 4.3.48(1)-release.
# It was not tested on other unix like operating systems.
#
# BUGS: ---
# NOTES: ---
# AUTHOR: Taras Drozdovskyi <t.drozdovskiy@gmail.com>
# VERSION: 0.1
# CREATED: 27.01.2018 - 12:36:50
# REVISION:
#==============================================================================

set -u # non initialized variable is an error

#-----------------------------------------------------------------------
# traps
#
# 2 signals are used: SIGUSR1 to decrease delay after level up and SIGUSR2 to quit
# they are sent to all instances of this script
# because of that we should process them in each instance
# in this instance we are ignoring both signals
#-----------------------------------------------------------------------

trap '' SIGUSR1 SIGUSR2

# Those are commands sent to controller by key press processing code
# In controller they are used as index to retrieve actual functuon from array
QUIT=0
RIGHT=1
LEFT=2
SHOT=3
DOWN=4
TOGGLE_HELP=5
TOGGLE_COLOR=6

DELAY=0.05          # initial delay between piece movements
DELAY_FACTOR=0.8    # this value controld delay decrease for each level up
DELAY_FALL_CONST=100
DELAY_FALL=$DELAY_FALL_CONST

# color codes
RED=1
GREEN=2
YELLOW=3
BLUE=4
FUCHSIA=5
CYAN=6
WHITE=7

# Location and size of playfield, color of border
PLAYFIELD_W=10
PLAYFIELD_H=20
PLAYFIELD_X=30
PLAYFIELD_Y=5
BORDER_COLOR=$YELLOW

#Location and color of game name
GAME_NAME="-=GALAXIAN=-"
GAME_NAME_X=34
GAME_NAME_Y=2
GAME_NAME_COLOR=$WHITE

# Location and color of score information
SCORE_X=1
SCORE_Y=5
SCORE_COLOR=$GREEN

# Location and color of help information
HELP_X=58
HELP_Y=5
HELP_COLOR=$CYAN

# Location of "game over" in the end of the game
GAMEOVER_X=$((PLAYFIELD_W / 2 + PLAYFIELD_X))
GAMEOVER_Y=$((PLAYFIELD_H / 2 + PLAYFIELD_Y))

# Intervals after which game level (and game speed) is increased 
LEVEL_UP=20

# Enemies number which appearing after start every level
ENEMY_NUMBER=20

colors=($RED $GREEN $YELLOW $BLUE $FUCHSIA $CYAN $WHITE)

no_color=true    # do we use color or not
showtime=true    # controller runs while this flag is true
empty_cell=" ."  # how we draw empty cell
filled_cell="[]" # how we draw filled cell
bullet_cell="*"
score=0           # score variable initialization
level=1           # level variable initialization
enemies_destroyed=0 # destroyed enemies counter initialization

# screen_buffer is variable, that accumulates all screen changes
# this variable is printed in controller once per game cycle
puts() {
  screen_buffer+=${1}
}

# move cursor to (x,y) and print string
# (1,1) is upper left corner of the screen
xyprint() {
  puts "\033[${2};${1}H${3}"
}

show_cursor() {
  echo -ne "\033[?25h"
}

hide_cursor() {
  echo -ne "\033[?25l"
}

# foreground color
set_fg() {
  $no_color && return
  puts "\033[3${1}m"
}

## background color
set_bg() {
  $no_color && return
  puts "\033[4${1}m"
}

reset_colors() {
  puts "\033[0m"
}

set_bold() {
  puts "\033[1m"
}

# playfield is 1-dimensional array, data is stored as follows:
# [ a11, a21, ... aX1, a12, a22, ... aX2, ... a1Y, a2Y, ... aXY]
#   |<  1st line   >|  |<  2nd line   >|  ... |<  last line  >|
# X is PLAYFIELD_W, Y is PLAYFIELD_H
# each array element contains cell color value or -1 if cell is empty
redraw_playfield() {
  local j i x y xp yp

  ((xp = PLAYFIELD_X))
  for ((y = 0; y < PLAYFIELD_H; y++)) {
    ((yp = y + PLAYFIELD_Y))
    ((i = y * PLAYFIELD_W))
    xyprint $xp $yp ""
      for ((x = 0; x < PLAYFIELD_W; x++)) {
        ((j = i + x))
        if ((${play_field[$j]} == -1)) ; then
          puts "$empty_cell"
        else
          set_fg ${play_field[$j]}
          set_bg ${play_field[$j]}
          puts "$filled_cell"
          reset_colors
        fi
      }
  }
}

show_game_name() {
  set_bold
  set_fg $GAME_NAME_COLOR
  xyprint $GAME_NAME_X $GAME_NAME_Y $GAME_NAME
  reset_colors
}

#=== FUNCTION =================================================================
# NAME:        update_score
# DESCRIPTION: Update score tin this game.
# PARAMETER 1: number of destroyed enemies
#==============================================================================
update_score() {
  ((enemies_destroyed += $1))
  # I provided own scoring algorithm for this game
  ((score += ((PLAYFIELD_H - current_enemy_y) * $1 * level)))
  if ((current_enemy_number == 0)) ; then      # if level should be increased
    ((score += (1000 * level)))
    set_bold
    set_fg $WHITE
    ((level++))                                  # increment level
    xyprint $((PLAYFIELD_W / 2 + PLAYFIELD_X + 2)) $((PLAYFIELD_H / 2 + PLAYFIELD_Y)) "LEVEL $level"
    reset_colors
    clear_spacecraft
    level_init
    pkill -SIGUSR1 -f "/bin/bash $0" # and send SIGUSR1 signal to all instances of this script (please see ticker for more details)
  fi
  set_bold
  set_fg $SCORE_COLOR
  xyprint $SCORE_X $SCORE_Y         "Enemies destroyed: $enemies_destroyed"
  xyprint $SCORE_X $((SCORE_Y + 1)) "Enemy's waves :    $level"
  xyprint $SCORE_X $((SCORE_Y + 2)) "Score:             $score"
  reset_colors
}

help=(
" Control keys:"
""
" <-, a: left"
" ->, d: right"
" ^, s: shot"
" c: toggle_color"
" h: toggle this help"
" q: quit"
)

help_on=-1 # if this flag is 1 help is shown

toggle_help() {
  local i s

  set_bold
  set_fg $HELP_COLOR
  for ((i = 0; i < ${#help[@]}; i++ )) {
    # ternary assignment: if help_on is 1 use string as is,
    # otherwise substitute all characters with spaces
    ((help_on == 1)) && s="${help[i]}" || s="${help[i]//?/ }"
    xyprint $HELP_X $((HELP_Y + i)) "$s"
  }
  ((help_on = -help_on))
  reset_colors
}

# this array holds all possible pieces that can be used in the game
# size of each piece can be consists of different number cells
# each string is sequence of relative xy coordinates for different orientations
piece=(
"00" #011011                                    # square (spacecraft,bullet)
"0001020304050607080910111213141516171819"      # line of enemy
)

piece_size=(
2
40
)

draw_piece() {
  # Arguments:
  # 1 - x, 2 - y, 3 - type, 4 cell content
  local i x y

  # loop through piece cells: piece_size cells, each has 2 coordinates
  for ((i = 0; i < piece_size[$3]; i += 2)) {
    # relative coordinates are retrieved based on orientation and added to absolute coordinates
    ((x = $1 + ${piece[$3]:$((i + 1)):1} * 2))
    ((y = $2 + ${piece[$3]:$((i)):1}))
    xyprint $x $y "$4"
  }
}

draw_spacecraft() {
  # Arguments: 1 - string to draw single cell
  # factor 2 for x because each cell is 2 characters wide
  draw_piece $((current_spacecraft_x * 2 + PLAYFIELD_X))  $((current_spacecraft_y + PLAYFIELD_Y)) $current_spacecraft "$1"
}

draw_bullet() {
  # Arguments: 1 - string to draw single cell
  # factor 2 for x because each cell is 2 characters wide
  draw_piece $((current_bullet_x * 2 + PLAYFIELD_X)) $((current_bullet_y + PLAYFIELD_Y)) $current_bullet "$1"
}

show_spacecraft() {
  set_fg $current_spacecraft_color
  set_bg $current_spacecraft_color
  draw_spacecraft "${filled_cell}"
  reset_colors
}

show_bullet() {
  set_fg $current_bullet_color
  set_bg $current_bullet_color   # comment this string, if you want to use other filled cell
  draw_bullet "${filled_cell}"   # provide type of the filled cell 
  reset_colors
}

clear_spacecraft() {
  draw_spacecraft "${empty_cell}"
}

clear_bullet() {
  draw_bullet "${empty_cell}"
}

new_spacecraft_location_ok() {
  # Arguments: 1 - new x coordinate of the piece, 2 - new y coordinate of the piece
  # test if piece can be moved to new location
  local j i x y x_test=$1 y_test=$2

  for ((j = 0, i = 1; j < 8; j += 2, i = j + 1)) {
      ((y = ${piece[$current_spacecraft]:$((j)):1} + y_test)) # new y coordinate of piece cell
      ((x = ${piece[$current_spacecraft]:$((i)):1} + x_test)) # new x coordinate of piece cell
      ((y < 0 || x < 0 || x >= PLAYFIELD_W )) && return 1         # check if we are out of the play field
  }
  return 0
}

new_bullet_location_ok() {
  # Arguments: 1 - new x coordinate of the piece, 2 - new y coordinate of the piece
  # test if piece can be moved to new location
  local j i x y x_test=$1 y_test=$2

  for ((j = 0, i = 1; j < 8; j += 2, i = j + 1)) {
      ((y = ${piece[$current_bullet]:$((j)):1} + y_test)) # new y coordinate of piece cell
      ((x = ${piece[$current_bullet]:$((i)):1} + x_test)) # new x coordinate of piece cell
      ((y < 0 || y >= PLAYFIELD_H || x < 0 || x >= PLAYFIELD_W )) && return 1         # check if we are out of the play field
      ((${play_field[((y * PLAYFIELD_W + x))]} != -1 )) && return 1                       # check if location is already ocupied
  }
  return 0
}

level_init() {
  local i
  # spacecraft & bullel piece becomes current
  current_spacecraft=0
  current_bullet=0
  current_enemy_color=$GREEN
  current_spacecraft_color=$BLUE
  current_bullet_color=$RED
  ((current_enemy_x = 0)) #(PLAYFIELD_W - 4) / 2))
  ((current_enemy_y = 0))
  # place current at the buttom of play field, approximately at the center
  ((current_spacecraft_x = (PLAYFIELD_W - 2) / 2))
  ((current_spacecraft_y = PLAYFIELD_H - 1))
  ((current_bullet_x = 0))
  ((current_bullet_y = 0))
  current_enemy_number=$ENEMY_NUMBER
  # check if piece can be placed at this location, if not - game over
  new_spacecraft_location_ok $current_spacecraft_x $current_spacecraft_y || cmd_quit
  show_spacecraft
  # mark cells as enemies
  for ((i = 0; i < PLAYFIELD_W * 2; i++)) {
    play_field[$i]=$current_enemy_color
  }
}

draw_border() {
  local i x1 x2 y

  set_bold
  set_fg $BORDER_COLOR
  ((x1 = PLAYFIELD_X - 2))               # 2 here is because border is 2 characters thick
  ((x2 = PLAYFIELD_X + PLAYFIELD_W * 2)) # 2 here is because each cell on play field is 2 characters wide
  for ((i = 0; i < PLAYFIELD_H + 1; i++)) {
      ((y = i + PLAYFIELD_Y))
      xyprint $x1 $y "||"
      xyprint $x2 $y "||"
  }
  ((y = PLAYFIELD_Y - 1))
  for ((i = 0; i < PLAYFIELD_W; i++)) {
      ((x1 = i * 2 + PLAYFIELD_X)) # 2 here is because each cell on play field is 2 characters wide
      xyprint $x1 $y '=='
  }

  ((y = PLAYFIELD_Y + PLAYFIELD_H))
  for ((i = 0; i < PLAYFIELD_W; i++)) {
      ((x1 = i * 2 + PLAYFIELD_X)) # 2 here is because each cell on play field is 2 characters wide
      xyprint $x1 $y '=='
      #xyprint $x1 $((y + 1)) "\/"
  }
  reset_colors
}

toggle_color() {
  $no_color && no_color=false || no_color=true
  show_game_name
  update_score 0
  toggle_help
  toggle_help
  draw_border
  redraw_playfield
  show_spacecraft
}

init() {
  local i x1 x2 y

  # playfield is initialized with -1s (empty cells)
  for ((i = 0; i < PLAYFIELD_H * PLAYFIELD_W; i++)) {
    play_field[$i]=-1
  }

  clear
  hide_cursor
  level_init
  toggle_color
}

# this function runs in separate process
# it sends DOWN commands to controller with appropriate delay
ticker() {
  # on SIGUSR2 this process should exit
  trap exit SIGUSR2
  # on SIGUSR1 delay should be decreased, this happens during level ups
  trap 'DELAY=$(awk "BEGIN {print $DELAY * $DELAY_FACTOR}")' SIGUSR1

  while true ; do echo -n $DOWN; sleep $DELAY; done
}

# this function processes keyboard input
reader() {
  trap exit SIGUSR2 # this process exits on SIGUSR2
  trap '' SIGUSR1   # SIGUSR1 is ignored
  local -u key a='' b='' cmd esc_ch=$'\x1b'
  # commands is associative array, which maps pressed keys to commands, sent to controller
  declare -A commands=([A]=$SHOT [C]=$RIGHT [D]=$LEFT
      [_S]=$SHOT [_A]=$LEFT [_D]=$RIGHT
      [_Q]=$QUIT [_H]=$TOGGLE_HELP [_C]=$TOGGLE_COLOR)

  while read -s -n 1 key ; do
      case "$a$b$key" in
          "${esc_ch}["[ACD]) cmd=${commands[$key]} ;; # cursor key
          *${esc_ch}${esc_ch}) cmd=$QUIT ;;           # exit on 2 escapes
          *) cmd=${commands[_$key]:-} ;;              # regular key. If space was pressed $key is empty
      esac
      a=$b   # preserve previous keys
      b=$key
      [ -n "$cmd" ] && echo -n "$cmd"
  done
}

# this function goes through play_field array and eliminates lines without empty sells
process_complete_lines() {
  local j i complete_lines
  ((complete_lines = 0))
  for ((j = 0; j < PLAYFIELD_W * PLAYFIELD_H; j += PLAYFIELD_W)) {
      for ((i = j + PLAYFIELD_W - 1; i >= j; i--)) {
          ((${play_field[$i]} == -1)) && break # empty cell found
      }
      ((i >= j)) && continue # previous loop was interrupted because empty cell was found
      ((complete_lines++))
      # move lines down
      for ((i = j - 1; i >= 0; i--)) {
        play_field[$((i + PLAYFIELD_W))]=${play_field[$i]}
      }
      # mark cells as free
      for ((i = 0; i < PLAYFIELD_W; i++)) {
        play_field[$i]=-1
      }
  }
  return $complete_lines
}

shift_playfield() {
  local x y
  for ((y = PLAYFIELD_H; y != 0; y--)) {
    for ((x = 0; x < PLAYFIELD_W; x++)) {
      play_field[$((y * PLAYFIELD_W + x))]=${play_field[(((y - 1) * PLAYFIELD_W + x))]}
    }
  }
  # mark cells as free
  for ((x = 0; x < PLAYFIELD_W; x++)) {
    play_field[$x]=-1
  }
}

process_fallen() {
  shift_playfield
  redraw_playfield
  show_spacecraft
}

move_spacecraft() {
  # arguments: 1 - new x coordinate, 2 - new y coordinate
  # moves the piece to the new location if possible
  if new_spacecraft_location_ok $1 $2 ; then  # if new location is ok
    clear_spacecraft                        # let's wipe out piece current location
    current_spacecraft_x=$1                 # update x ...
    current_spacecraft_y=$2                 # ... and y of new location
    show_spacecraft                         # and draw piece in new location
    return 0                          # nothing more to do here
  fi                                    # if we could not move piece to new location
}

move_bullet() {
  # arguments: 1 - new x coordinate, 2 - new y coordinate
  # moves the piece to the new location if possible
  if new_bullet_location_ok $1 $2 ; then # if new location is ok
    clear_bullet                        # let's wipe out piece current location
    current_bullet_x=$1                # update x ...
    current_bullet_y=$2                # ... and y of new location
    show_bullet                       # and draw piece in new location
    return 0                          # nothing more to do here
  else
    if [ ${play_field[(($2 * PLAYFIELD_W + $1))]} != -1 ] ; then
      play_field[(($2 * PLAYFIELD_W + $1))]=-1
      clear_bullet
      redraw_playfield
      show_spacecraft
      current_bullet_y=0
      ((current_enemy_number--))
      update_score 1
    fi
  fi                                    # if we could not move piece to new location
  clear_bullet
}

cmd_right() {
  move_spacecraft $((current_spacecraft_x + 1)) $current_spacecraft_y
}

cmd_left() {
  move_spacecraft $((current_spacecraft_x - 1)) $current_spacecraft_y
}

cmd_shot() {
  if [ $current_bullet_y -eq 0 ] ; then
    current_bullet_x=$current_spacecraft_x
    current_bullet_y=$current_spacecraft_y
    move_bullet $current_bullet_x $((current_bullet_y - 2))
    show_spacecraft
  fi
}

cmd_down() {
  local i
  if [ $current_bullet_y != 0 ] ; then
    move_bullet $current_bullet_x $((current_bullet_y - 1))
  else
    clear_bullet
  fi

  if [ $DELAY_FALL -eq 0 ] ; then
    DELAY_FALL=$DELAY_FALL_CONST

    for ((i = 0; i < PLAYFIELD_W; i++)) { 
      ((${play_field[(((PLAYFIELD_H - 2) * PLAYFIELD_W + $i))]} != -1 )) && cmd_quit   # check if location is out of the play field
    }
    ((current_enemy_y++))
    process_fallen
  else
    ((DELAY_FALL--))
  fi
}

cmd_quit() {
  showtime=false                               # let's stop controller ...
  pkill -SIGUSR2 -f "/bin/bash $0" # ... send SIGUSR2 to all script instances to stop forked processes ...
  set_bold
  set_fg $WHITE
  xyprint $GAMEOVER_X $GAMEOVER_Y "GAME OVER!"
  reset_colors
  #xyprint $GAMEOVER_X $GAMEOVER_Y "Game over!\n\n"
  xyprint 0 $((PLAYFIELD_H + PLAYFIELD_Y)) "\n\n"
  echo -e "$screen_buffer"                     # ... and print final message
}

controller() {
  # SIGUSR1 and SIGUSR2 are ignored
  trap '' SIGUSR1 SIGUSR2
  local cmd commands

  # initialization of commands array with appropriate functions
  commands[$QUIT]=cmd_quit
  commands[$RIGHT]=cmd_right
  commands[$LEFT]=cmd_left
  commands[$SHOT]=cmd_shot
  commands[$DOWN]=cmd_down
  commands[$TOGGLE_HELP]=toggle_help
  commands[$TOGGLE_COLOR]=toggle_color

  init

  while $showtime; do           # run while showtime variable is true, it is changed to false in cmd_quit function
    echo -ne "$screen_buffer" # output screen buffer ...
    screen_buffer=""          # ... and reset it
    read -s -n 1 cmd          # read next command from stdout
    ${commands[$cmd]}         # run command
  done
}

stty_g=`stty -g` # let's save terminal state

# output of ticker and reader is joined and piped into controller
(
  ticker & # ticker runs as separate process
  reader
)|(
  controller
)

show_cursor
stty $stty_g # let's restore terminal state

