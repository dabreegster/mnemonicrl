#####################
# Interface::Curses #
#####################

package Roguelike::Interface::Curses;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Curses;

END {
  endwin();
}

sub create {
  my $class = shift;
  my $layout = shift;
  # Initialize Curses and color and stuff.
  initscr();
  noecho();
  curs_set(0);
  start_color();
  keypad(1);
  init_pair(1,  COLOR_BLACK,   COLOR_BLACK);
  init_pair(2,  COLOR_RED,     COLOR_BLACK);
  init_pair(3,  COLOR_GREEN,   COLOR_BLACK);
  init_pair(4,  COLOR_YELLOW,  COLOR_BLACK);
  init_pair(5,  COLOR_BLUE,    COLOR_BLACK);
  init_pair(6,  COLOR_MAGENTA, COLOR_BLACK);
  init_pair(7,  COLOR_CYAN,    COLOR_BLACK);
  init_pair(8,  COLOR_WHITE,   COLOR_BLACK);
  init_pair(9,  COLOR_BLACK,   COLOR_WHITE);
  init_pair(10, COLOR_RED,     COLOR_WHITE);
  init_pair(11, COLOR_GREEN,   COLOR_WHITE);
  init_pair(12, COLOR_YELLOW,  COLOR_WHITE);
  init_pair(13, COLOR_BLUE,    COLOR_WHITE);
  init_pair(14, COLOR_MAGENTA, COLOR_WHITE);
  init_pair(15, COLOR_CYAN,    COLOR_WHITE);
  init_pair(16, COLOR_WHITE,   COLOR_WHITE);
  getmaxyx(my $rows, my $cols);
  my $self = bless { MaxY => $rows, MaxX => $cols }, $class;
  # Create every window in the layout.
  while (my ($window, $info) = each %{$layout}) {
    $info->{Size}[0] =~ s#(\d+)%#$1 * $rows / 100#;
    $info->{Size}[1] =~ s#(\d+)%#$1 * $cols / 100#;
    $info->{At}[0] =~ s#(\d+)%#$1 * $rows / 100#;
    $info->{At}[1] =~ s#(\d+)%#$1 * $cols / 100#;
    my $sizeY = int eval($info->{Size}[0]);
    my $sizeX = int eval($info->{Size}[1]);
    my $posY = int eval($info->{At}[0]);
    my $posX = int eval($info->{At}[1]);
    my $win = newwin($sizeY, $sizeX, $posY, $posX);
    $win->box(0, 0) if $info->{Border};
    $win->refresh;
    $self->{$window} = $win;
    $self->{"${window}Y"} = $sizeY - 4;
    $self->{"${window}X"} = $sizeX - 6;
  }
  $self->{ConsoleY} = $rows - 4;
  $self->{ConsoleX} = $cols - 6;
  return $self;
}

sub trans_symbol {
  shift;
  my $symbol = shift;
  return Curses->can($symbol) if $symbol =~ m/^ACS_/;
  return $symbol;
}

sub trans_color {
  shift;
  my $input = shift;
  my $lightbg = shift;
  # The only brightness we worry about now is the '!green' form.
  my $bright = 0;
  $bright = 1 if $input =~ s/^\!//;
  my %colors = (
    b => 5, # Blue
    r => 2, # Red
    g => 3, # Green
    a => 7, # Aqua/Cyan
    p => 6, # Purple/Magenta
    o => 4, # Orange
    y => 4, # Yellow
    k => 1, # Black
    e => 8, # Grey
    w => 8, # White
    # These should be self-explanatory, I hope.
    blue   => 5,
    red    => 2,
    green  => 3,
    aqua   => 7,
    cyan   => 7,
    purple => 6,
    orange => 4,
    yellow => 4,
    black  => 1,
    grey   => 8,
    gray   => 8,
    white  => 8
  );
  my $color = $colors{lc $input};
  $color += 8 if $lightbg;
  # Now we determine whether we're bright or dim.
  # If our first letter is capitalized, we're bright.
  $bright = 1 if substr($input, 0, 1) eq uc substr($input, 0, 1);
  # But then we have all these special cases. Simplify input.
  $input = lc $input;
  $bright = 0 if $input eq "o" or $input eq "orange";
  $bright = 1 if $input eq "y" or $input eq "yellow";
  $bright = 0 if $input eq "e" or $input eq "grey" or $input eq "gray";
  $bright = 1 if $input eq "w" or $input eq "white";
  my $attrib = $bright ? A_BOLD() : A_NORMAL();
  return ($attrib, COLOR_PAIR($color));
}

sub draw {
  my $self = shift;
  $self->{Display}->erase;  # /clear
  $self->{Display}->standend;
  $self->{Display}->box(0, 0) if $Game->{UI}{Layout}{Display}{Border};
  my $y = 0;
  foreach my $row (@_) {
    if ($Game->{FastRefresh}) {
      $self->{Display}->addstr(2 + $y, 1, join "", map {$_->{_SYMBOL_}} @$row);
    } else {
      my $x = 1;
      foreach my $tile (@{ $row }) {
        $self->{Display}->standend;
        $self->{Display}->attron($tile->{_ATTRIB_});
        $self->{Display}->attron($tile->{_COLOR_});
        $self->{Display}->addch(2 + $y, 3 + $x, $tile->{_SYMBOL_});
        $x++;
      }
    }
    $y++;
  }
  $self->{Display}->refresh;
}

sub msgdraw {
  my $self = shift;
  $self->{MsgConsole}->erase;  # /clear
  $self->{MsgConsole}->standend;
  $self->{MsgConsole}->box(0, 0) if $Game->{UI}{Layout}{MsgConsole}{Border};
  my $y = 0;
  foreach my $line (@_) {
    $self->{MsgConsole}->standend;
    my $x = 0;
    # Split by <\w+> and print the color codes in the right spots.
    foreach my $string (split(/(<\w+>)/, $line)) {
      if ($string =~ m/<(\w+)>/) {
        $self->{MsgConsole}->standend;
        my ($attrib, $color) = $self->trans_color($1);
        $self->{MsgConsole}->attron($attrib);
        $self->{MsgConsole}->attron($color);
      } else {
        $self->{MsgConsole}->addstr(1 + $y, 2 + $x, $string);
        $x += length $string;
      }
    }
    $y++;
  }
  $self->{MsgConsole}->refresh;
}

sub prompt {
  return getc;
}

sub display {
  my $self = shift;
  my $mode = shift; # 0=Init, 1=Display, 2=Close
  if ($mode == 0) {
    # Get ready to rumble
    $self->{Console}->erase;
    return 1;
  } elsif ($mode == 2) {
    # Get ready to... um... do the opposite of rumbling
    $Game->{UI}->refresh;
    $Game->{UI}->msgrefresh(1);
    $Game->{UI}->statrefresh;
    return 1;
  }
  # Display some stuff
  $self->{Console}->erase;  # /cl
  $self->{Console}->standend;
  $self->{Console}->box(0, 0) if $Game->{UI}{Layout}{Console}{Border};;
  my $y = 0;
  foreach my $line (@_) {
    $self->{Console}->standend;
    next unless defined $line;
    my $x = 0;
    # Split by <\w+> and print the color codes in the right spots.
    foreach my $string (split(/(<\w+>)/, $line)) {
      if ($string =~ m/<(\w+)>/) {
        $self->{Console}->standend;
        my ($attrib, $color) = $self->trans_color($1);
        $self->{Console}->attron($attrib);
        $self->{Console}->attron($color);
      } else {
        $self->{Console}->addstr(2 + $y, 3 + $x, $string);
        $x += length $string;
      }
    }
    $y++;
  }
  $self->{Console}->refresh;
}

sub statdraw {
  my $self = shift;
  $self->{Status}->erase;  # /clear
  $self->{Status}->standend;
  $self->{Status}->box(0, 0) if $Game->{UI}{Layout}{Status}{Border};
  my $y = 0;
  foreach my $line (@_) {
    $self->{Status}->standend;
    my $x = 0;
    # Split by <\w+> and print the color codes in the right spots.
    foreach my $string (split(/(<\w+>)/, $line)) {
      if ($string =~ m/<(\w+)>/) {
        $self->{Status}->standend;
        my ($attrib, $color) = $self->trans_color($1);
        $self->{Status}->attron($attrib);
        $self->{Status}->attron($color);
      } else {
        $self->{Status}->addstr(1 + $y, 2 + $x, $string);
        $x += length $string;
      }
    }
    $y++;
  }
  $self->{Status}->refresh;
}

sub msgbox {
  my $self = shift;
  my $mode = shift;
  return 1 if $mode == 0;
  if ($mode == 2) {
    # Unrumble, guys!
    $Game->{UI}->refresh;
    $Game->{UI}->msgrefresh(1);
    $Game->{UI}->statrefresh;
    return 1;
  }
  # Mode 0 is useless... we have to erase every time anyway.
  # Get the Console going
  $self->{Console}->erase;
  $self->{Console}->standend;
  $self->{Console}->box(0, 0) if $Game->{UI}{Layout}{Console}{Border};;
  # Longest line? Align left.
  my $length = 0;
  foreach (@_) {
    my $testline = $_;
    $testline =~ s/<\w+>//g;
    $length = length $testline if length $testline > $length;
  }
  my @lines = (" " x ($length + 2));
  foreach (@_) {
    my $line = $_;
    my $testline = $line;
    $testline =~ s/<\w+>//g;
    $line .= " " x ($length - length($testline));
    $line = " $line ";
    push @lines, $line;
  }
  push @lines, " " x ($length + 2);
  # Add space to ends of lines. PAD!
  my $y = ($self->{MaxY} - @_) / 2 - 1;
  foreach my $line (@lines) {
    $self->{Console}->standend;
    # Set background to white.
    my ($attrib, $color) = $self->trans_color("black", 1);
    $self->{Console}->attron($color);
    $self->{Console}->attron($attrib);
    my $x = ($self->{MaxX} - $length) / 2 - 2;
    # Split by <\w+> and print the color codes in the right spots.
    foreach my $string (split(/(<\w+>)/, $line)) {
      if ($string =~ m/<(\w+)>/) {
        $self->{Console}->standend;
        ($attrib, $color) = $self->trans_color($1, 1);
        $self->{Console}->attron($attrib);
        $self->{Console}->attron($color);
      } else {
        $self->{Console}->addstr(1 + $y, 2 + $x, $string);
        $x += length $string;
      }
    }
    $y++;
  }
  $self->{Console}->refresh;
  while (1) {
    last if $self->prompt eq " ";
  }
  return 1;
}

sub cursor {
  my ($self, $y, $x, $attrib, $color, $char) = @_;
  # Set y,x on Display to attrib and color.
  $self->{Display}->move($y, $x);
  $self->{Display}->standend;
  $self->{Display}->attron($attrib);
  $self->{Display}->attron($color);
  $self->{Display}->echochar($char);
  return 1;
}

42;
