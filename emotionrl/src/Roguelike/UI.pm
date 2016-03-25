######
# UI #
######

package Roguelike::UI;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Roguelike::Interface::Curses;
use Text::Wrap;

sub select {
  # I guess we can actually define other windows and stuff, but for now we only
  # use these standard three.
  my $layout = {
    Display => { At => [0, 0], Size => ["100% - 7", "60%"], Border => 1 },
    Status  => { At => [0, "60%"], Size => ["100% - 7", "40%"], Border => 1 },
    MsgConsole => { At => ["100% - 7", 0], Size => [7, "100%"], Border => 1 },
    Console => { At => [0, 0], Size => ["100%", "100%"], Border => 1 }
  };
  my $tiles = {
    " " => {
      Symbol => " ",
      Type   => "space",
    },
    "." => {
      Symbol => ".",
      Type   => "ground",
    },
    "#" => {
      Symbol  => "#",
      Color   => "orange",
      Type    => "wall",
      Barrier => 1
    },
    "+" => {
      Symbol  => "+",
      Type    => "closed door",
      Barrier => 1
    },
    "'" => {
      Symbol => "'",
      Type   => "open door"
    },
    "<" => {
      Symbol => "<",
      Type   => "staircase up"
    },
    ">" => {
      Symbol => ">",
      Type   => "staircase down"
    },
    "*" => {
      Symbol => "*",
      Color => "Yellow",
      Type => "debug"
    },
    "~" => {
      Symbol => "~",
      Color  => "Blue",
      Type   => "wave"
    },
    "-" => {
      Symbol => "-",
      Color  => "Black",
      Type   => "railing",
      Barrier => 1
    },
  };
  my $statbar = [
    "<green>PerlRL",
    "",
    sub {
      return (
        "<red>Turn:<grey> $Game->{Turns}",
        "<BLUE>Z:<grey> " . $Player->g("Z"),
        "<BLUE>Y:<grey> " . $Player->g("Y"),
        "<BLUE>X:<grey> " . $Player->g("X")
      );
    },
    "",
    sub {
      return (
        "<PURPLE>HP:<grey> " . $Player->g("HP") . "/" . $Player->g("MaxHP"),
        "<PURPLE>TP:<grey> " . $Player->g("TP") . "/" . $Player->g("MaxTP"),
        "<PURPLE>Str:<grey> " . $Player->g("Str"),
        "<PURPLE>Def:<grey> " . $Player->g("Def"),
      );
    },
    "",
    sub {
      my $now = $Player->g("Exp");
      my $left = $Player->g("ExpNeeded");
      return (
        "<aqua>Exp:<grey> $now/$left",
        "<aqua>Level:<grey> " . $Player->g("Level")
      );
    },
    "",
    sub {
      my $status = $Player->g("Laughing") ? "Laughing" : "Normal";
      my $mons = "<Green>Monsters:<grey> " . @{ $Player->g("Area.Monsters") };
      my $weapon = "Unarmed";
      if ($Player->g("Equipment.Weapon")) {
        $weapon = $Player->g("Equipment.Weapon")->name;
        $weapon =~ s/ \(wielded\)$//;
      }
      return ("<Cyan>Status:<grey> $status", $mons, "<Black>$weapon");
    },
  ];
  # For lack of a better way to do this...
  $tiles->{space} = $tiles->{" "};
  $tiles->{ground} = $tiles->{"."};
  $tiles->{wall} = $tiles->{"#"};
  my $self = bless {
    Tiles      => $tiles,
    StatLayout => $statbar,
    MsgFilters => [
      sub { my $msg = shift; $msg =~ s/\[DEBUG\]/<RED>[DEBUG]/g; return $msg; },
      sub { my $msg = shift; $msg =~ s/\[WARN\]/<RED>[WARN]/g; return $msg; }
    ],
    Layout     => $layout,  # For later reference
    # Real intelligent choosing of interface, eh? There's just so much
    # selection right now.
    Interface  => Roguelike::Interface::Curses->create($layout)
  }, shift;
  # Well I guess we do this.
  $self->{Interface}{TilesN} = int (($self->{Interface}{DisplayY} - 1) / 2);
  $self->{Interface}{TilesS} = $self->{Interface}{DisplayY} -
                               $self->{Interface}{TilesN} - 1;
  $self->{Interface}{TilesE} = int (($self->{Interface}{DisplayX} - 1) / 2);
  $self->{Interface}{TilesW} = $self->{Interface}{DisplayX} -
                               $self->{Interface}{TilesE} - 1;
  return $self;
}

sub refresh {
  my $self = shift;
  my $map = $Player->g("Area");
  my $wrap = $Player->g("Area.Wrap");
  my $y = $Player->g("Y");
  my $x = $Player->g("X");
  my $n = $self->{Interface}{TilesN};
  my $s = $self->{Interface}{TilesS};
  my $e = $self->{Interface}{TilesE};
  my $w = $self->{Interface}{TilesW};
  # Calculate the Y offsets.
  my @rows = ();
  if ($map->height >= $self->{Interface}{DisplayY}) {
    my ($start, $end);
    if ($y - $n < 0 and (!$wrap)) {
      $start = 0;
    } else {
      $start = $y - $n;
    }
    push @rows, $_ foreach ($start .. $y);
    if ($y + $s > $map->height) {
      $end = $map->height;
    } else {
      $end = $y + $n;
    }
    push @rows, $_ foreach ($y + 1 .. $end);
    # I can't remember what all this is supposed to do; all I know is that it
    # works and that it took me a while to get going.
    my $spare = $self->{Interface}{DisplayY} - scalar @rows;
    my $sparewrap = 0;
    foreach (1 .. $spare) {
      if ($wrap) {
        push(@rows, $sparewrap++);
      } else {
        if ($map->{Map}[ $rows[-1] + 1 ]) {
          push @rows, $rows[-1] + 1;
        } else {
          unshift @rows, $rows[0] - 1;
        }
      }
    }
  } else {
    @rows = (0 .. $map->height);
  }
  # Calculate the X offsets.
  my @cols = ();
  if ($map->width >= $self->{Interface}{DisplayX}) {
    my ($start2, $end2);
    if ($x - $w < 0 and (!$wrap)) {
      $start2 = 0;
    } else {
      $start2 = $x - $w;
    }
    push @cols, $_ foreach ($start2 .. $x);
    if ($x + $e > $map->width) {
      $end2 = $map->width;
    } else {
      $end2 = $x + $e;
    }
    push @cols, $_ foreach ($x + 1 .. $end2);
    # I can't remember what all this is supposed to do; all I know is that it
    # works and that it took me a while to get going.
    my $spare2 = $self->{Interface}{DisplayX} - scalar @cols;
    my $sparewrap2 = 0;
    foreach (1 .. $spare2) {
      if ($wrap) {
        push(@cols, $sparewrap2++);
      } else {
        if ($map->{Map}[0][ $cols[-1] + 1 ]) {
          push @cols, $cols[-1] + 1;
        } else {
          unshift @cols, $cols[0] - 1;
        }
      }
    }
  } else {
    @cols = (0 .. $map->width);
  }
  # No we draw, gentlemen.
  # Since $wrap might be on and the list unordered, making select obselete,
  # we'll just do it ourselves.
  my @tilerows;
  my %list;
  foreach my $Y (@rows) {
    my $cols = [];
    foreach my $X (@cols) {
      push @$cols, $map->{Map}[$Y][$X];
      if ($map->{Map}[$Y][$X]{Char} and $map->{Map}[$Y][$X]{Char}{ID} !=
          $Player->g("ID")
         )
      {
        $list{ $map->{Map}[$Y][$X]{Char}{ID} } = 1;
      }
    }
    push @tilerows, $cols;
  }
  $Game->{Top} = $rows[0];
  $Game->{Bottom} = $rows[-1];
  $Game->{Left} = $cols[0];
  $Game->{Right} = $cols[-1];
  $Game->{Active} = \%list;
  $self->{Interface}->draw(@tilerows);
}

sub msgrefresh {
  my $self = shift;
  my $keep = shift || 0;  # Move this turn's messages to the log?
  $Text::Wrap::columns = $self->{Interface}{MsgConsoleX};
  # We only want to display 5 physical lines. So we have to factor in word wrap!
  # It's always 5 physical lines because of the layout. I'll make it
  # customizable later.
  # First we get the last 5 messages.
  # I wrote this code ages ago and, like the 'spare' bit in refresh(), I have
  # no clue how it works anymore, only that it does and that it wasn't fun to
  # write.
  my @msgs;
  if (scalar @{ $Game->{Messages} } <= 5) {
    push @msgs, $Game->{Messages}[-5 + $_] foreach 0 .. 4;
  } else {
    @msgs = @{ $Game->{Messages} };
  }
  # Now factor in word wrap.
  my @lines = map { split(/\n/, wrap("", "", $_)) } @msgs;
  # Finally we have lines to display. Get the last 5, literally.
  my @sayme;
  if (scalar @lines > 5) {
    @sayme = map { $lines[-$_] } (1 .. 5);
    @sayme = reverse @sayme;
  } else {
    @sayme = @lines;
  }
  # Apply filters to the lines.
  my @sendme;
  # It's not like this is horribly slow and inefficent or anything.
  foreach my $line (@sayme) {
    foreach my $filter (@{$self->{MsgFilters}}) {
      $line = $filter->($line);
    }
    push @sendme, $line;
  }
  # Now we talk to the player, gentlemen. Gah, doesn't sound cool.
  $self->{Interface}->msgdraw(@sendme);
  unless ($keep) {
    # Don't repeatedly log messages!
    push @{ $Game->{MsgLog} }, @{ $Game->{Messages} };
    # Are we full?
    if (@{ $Game->{MsgLog} } > 100) {
      my $times = @{ $Game->{MsgLog} } - 100;
      shift @{ $Game->{MsgLog} } foreach 1 .. $times;
    }
    $Game->{Messages} = [];
  }
}

sub statrefresh {
  my $self = shift;
  my @lines = ();
  foreach (@{ $self->{StatLayout} }) {
    if (ref $_ eq "CODE") {
      push @lines, $_->();
    } else {
      push @lines, $_;
    }
  }
  $self->{Interface}->statdraw(@lines);
}

sub prompt {
  my $self = shift;
  return $self->{Interface}->prompt;
}

sub display {
  my $self = shift;
  $self->{Interface}->display(0);
  my $mode = shift;
  my $filters = shift;
  my @msgs = @_;
  # First we format the lines using word wrap.
  $Text::Wrap::columns = $self->{Interface}{ConsoleX};
  # Factor in word wrap.
  my @sayme = map {
    if ($_) {
      split(/\n/, wrap("", "", $_))
    } else {
      $_;
    }
  } @msgs;
  # Apply filters to the lines.
  my @lines;
  # It's not like this is horribly slow and inefficent or anything.
  foreach my $line (@sayme) {
    foreach my $filter (@{ $filters }) {
      $line = $filter->($line);
    }
    push @lines, $line;
  }
  # Now @lines contains the formatted lines to display. Use a simplified
  # version of the refresh routine to figure out which lines to display.
  my $y = 0;
  my $return = 1;
  my $first = 1;
  while (1) {
    my $y1 = 0;
    my $y2 = scalar @lines;
    if (scalar @lines > $self->{Interface}{ConsoleY}) {
      $y1 = $y;
      $y2 = $y1 + $self->{Interface}{ConsoleY} - 1;
      if ($first) {
        $first = 0;
        $y = $y1 = scalar @lines - $self->{Interface}{ConsoleY};
        $y2 = scalar @lines;
      }
    }
    # Select the lines.
    my @draw;
    push @draw, $lines[$_] foreach $y1 .. $y2;
    $self->{Interface}->display(1, @draw);
    # Now, finally do input.
    my $in = $Game->{UI}->prompt;
    if ($mode == 0) {
      $y++ if $in eq "j";
      $y-- if $in eq "k";
      $y++ if $y < 0;
      $y-- if $y > $#lines;
      last if $in eq "x" or $in eq " " or $in eq "";
    } else {
      $return = $in;
      last;
    }
  }
  $self->{Interface}->display(2);
  return $return;
}

sub selectinv {
  my $self = shift;
  my $obj = shift;
  my $msg = shift;
  my $categories = shift || [];
  my $literal = shift || [];
  my %literal = map { $_ => 1 } @$literal;
  while (1) {
    say $msg;
    $self->msgrefresh(1);
    my $in = $self->prompt;
    if ($in eq "" or $in eq " ") {
      say "Never mind.";
      return -1;
    } else {
      if ($in eq "?") {
        if (scalar @$categories) {
          # Do we have anything in the categories?
          my $any = 0;
          foreach (@$categories) {
            my $cat = $obj->g("Inv.Category.$_") || {};
            $any++, last if keys %$cat;
          }
          unless ($any) {
            say "You don't have anything like that!";
            return -1;
          }
          $in = $Player->inv(1, @{ $categories });
        } else {
          $in = $Player->inv(1);
        }
      }
      if ($in eq " " or $in eq "") {
        say "Never mind.";
        return -1;
      }
      return $in if $literal{$in};
      my $return = $obj->{Inv}->get($in);
      unless ($return) {
        say "You don't have that.";
        $Game->{UI}->msgrefresh(1);
        next;
      }
      return $return;
    }
  }
}

sub selectchoice {
  my $self = shift;
  my $choices = shift;
  my $msg = shift;
  while (1) {
    say $msg;
    $self->msgrefresh(1);
    my $in = $self->prompt;
    if ($in eq "" or $in eq " ") {
      say "Never mind.";
      return -1;
    } else {
      if (defined $choices->{$in}) {
        return $choices->{$in};
      } else {
        say "Huh?";
        $Game->{UI}->msgrefresh(1);
        next;
      }
    }
  }
}

sub selecttech {
  my $self = shift;
  while (1) {
    say "Perform which technique?";
    $self->msgrefresh(1);
    my $in = $self->prompt;
    if ($in eq "" or $in eq " ") {
      say "Never mind.";
      return -1;
    } else {
      if ($in eq "?") {
        my @lines = ("<yellow>Techniques", "");
        my $letter = "a";
        foreach (sort keys %{ $Player->g("Techniques") }) {
          # $letter - Name (Cost: $cost) [Success: $success]
          # Desc
          #
          # Easy.
          my $letter = $_;
          $_ = $Player->g("Techniques.$letter");
          my $line = "$letter - $_->{Name} (Cost: ";
          $line .= $Player->g("Attacks.$_->{Name}.TP");
          $line .= ") [Success: ";
          $line .= "Bad" if $_->{Success} == 1;
          $line .= "Good" if $_->{Success} == 2;
          $line .= "Perfect" if $_->{Success} == 3;
          $line .= "]";
          push @lines, $line, $Player->g("Techniques.$letter.Desc"), "";
        }
        $in = $self->display(1, [], @lines);
      }
      if ($in eq " " or $in eq "") {
        say "Never mind.";
        return -1;
      }
      # Do we have technique $in?
      unless ($Player->g("Techniques.$in")) {
        say "You don't possess that technique.";
        $Game->{UI}->msgrefresh(1);
        next;
      }
      return $in;
    }
  }
}

sub msgbox {
  my $self = shift;
  my $mode = shift;
  if ($mode != 1) {
    $self->{Interface}->msgbox($mode);
    return 1;
  }
  # It'll be the same for the Console
  $Text::Wrap::columns = $self->{Interface}{MsgConsoleX} - 8;
  # Blasted vim editing style.
  my @lines;
  foreach (@_) {
    my $line = $_;
    $line =~ s/\n/ /g;
    $line =~ s/\s+/ /g;
    push @lines, $line;
  }
  my $width = $self->{Interface}{MsgConsoleX} - 8;
  my @msgs;
  foreach (@lines) {
    my $realline = "";
    my $line = "";
    # My homegrown word wrap that disregards <color> tags!
    foreach my $realword (split(/\s/, $_)) {
      # Strip the word first.
      my $word = $realword;
      $word =~ s/<[^>]+>//g;
      if (length($line) + length($word) + 1 <= $width) {
        $word = " $word" unless length($line) == 0;
        $realword = " $realword" unless length($realline) == 0;
        $line .= $word;
        $realline .= $realword;
      } else {
        push @msgs, $realline;
        $line = $word;
        $realline = $realword;
      }
    }
    # Leftovers!
    push @msgs, $realline;
  }
  # Display. Whew.
  $self->{Interface}->msgbox(1, @msgs);
  return 1;
}

sub target {
  my $self = shift;
  say "Use hjklyunm to move, ? to examine a baddie, and space or escape to quit.";
  $self->msgrefresh;
  # We interact directly with the Interface for simplicity. Sorry.
  # Start the cursor at the Player.
  my $map = $Player->g("Area.Map");
  my ($mapY, $mapX) = ($Player->g("Y"), $Player->g("X"));
  my $screeny = (2 + $mapY - $Game->{Top});
  my $screenx = (4 + $mapX - $Game->{Left});
  $self->{Interface}->cursor(
    $screeny,
    $screenx,
    $self->{Interface}->trans_color("Blue", 1),
    $map->[$mapY][$mapX]{_SYMBOL_},
  );
  while (1) {
    my $key = $Game->{UI}->prompt;
    if ($key eq "?") {
      # NOW we can examine something! But is there a character there?
      if ($map->[$mapY][$mapX]{Char}) {
        $Player->examinemons($map->[$mapY][$mapX]{Char});
      } else {
        say "There isn't an actor here!";
      }
    }
    # Erase old character.
    $self->{Interface}->cursor(
      $screeny,
      $screenx,
      $map->[$mapY][$mapX]{_ATTRIB_},
      $map->[$mapY][$mapX]{_COLOR_},
      $map->[$mapY][$mapX]{_SYMBOL_},
    );
    if ($key eq " " or $key eq "" or $key eq "x" or $key eq "") {
      # Bye!
      last;
    }
    # OK, so we move.
    $mapY-- if $key eq "k";
    $mapY++ if $key eq "j";
    $mapX-- if $key eq "h";
    $mapX++ if $key eq "l";
    $mapY--, $mapX-- if $key eq "y";
    $mapY--, $mapX++ if $key eq "u";
    $mapY++, $mapX-- if $key eq "b";
    $mapY++, $mapX++ if $key eq "n";
    # Out of boundaries?
    if ($mapY > $Game->{Bottom}) {
      $mapY--;
    } elsif ($mapY < $Game->{Top}) {
      $mapY++;
    }
    if ($mapX > $Game->{Right}) {
      $mapX--;
    } elsif ($mapX < $Game->{Left}) {
      $mapX++;
    }
    # Right, so calculate the new screen offset and display the cursor.
    $screeny = (2 + $mapY - $Game->{Top});
    $screenx = (4 + $mapX - $Game->{Left});
    $self->{Interface}->cursor(
      $screeny,
      $screenx,
      $self->{Interface}->trans_color("Blue", 1),
      $map->[$mapY][$mapX]{_SYMBOL_},
    );
    # Finally, display what we've got on the current tile in the messagebar.
    say $map->[$mapY][$mapX]{Char} ? $map->[$mapY][$mapX]{Char}->name : "";
    $self->msgrefresh;
  }
  return ($mapY, $mapX);
}

42;
