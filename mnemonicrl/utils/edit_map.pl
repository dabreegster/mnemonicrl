#!/usr/bin/perl

# TODO take over escape and enter key
# TODO make sure modes dont trample on each other
# TODO reset modes when we change maps

use strict;
use warnings;
use lib "../../perlrl";
use lib "../..";
use Util;

use HexedUI::Interface;
use PerlRL::Component::View;
use PerlRL::Component::View::Effects;
use Game::Timing;
use BDSM::Map;
use BDSM::Toy::Conveyor;

package Null;
use Util;
bless GAME, "Null";
GAME->{NoMapPostProc} = 1;
sub fullsim { 0 }
sub schedule { shift()->{Timers}->schedule(@_); }
sub unschedule { shift()->{Timers}->unschedule(@_); }

package main;

my ($map, $fn, %brush);
my ($freehand, $stretch, @oldstretch, $movetoy, $layer);
my $before_toy = {};
my ($start_y, $start_x) = (0, 0);

my $ui = cast HexedUI::Interface {
  FPS    => 1.0 / 30,
  Keymap => "../../Keymap",
  Brush  => {
    Type    => "Form",
    At      => ["0", "75% - 1"],
    Size    => ["14", "25% + 2"],
    Border  => 1,
    Entries => [
      [[Header  => "Current tile:"]],
      [[At      => "_, _"]],
      [[Tile    => "Tile: _"]],
      [[Type    => "Type: _"]],
      #[[Extra   => "Extra: _ = _"]], # TODO no easy way to show this?
      [[Msg     => "_"]],
      [],
      [[BHeader  => "Brush:"]],
      [[BSymbol  => "Tile symbol: _"]],
      [[BColor   => "Color: _"]],
      [[BType    => "Type: _"]],
      [[BExtra   => "+: _ = _"]],
    ]
  },
  Main => {
    Type   => "Map",
    At     => [0, 0],
    Size   => ["100%", "75% - 1"],
    #Size => ["100%", "100%"],
    Border => "Green",
    Pad    => 1
  },
  Msgs => {
    Type   => "Msg",
    At     => ["14", "75% - 1"],
    Size   => ["100% - 14", "25% + 2"],
    Border => 1
  }
};

GAME->{UI} = $ui;
msg(-set => $ui->{Msgs});

sub menu {
  my @choices = ("Open existing map", "Start a new map", "Quit");
  push @choices, ("Save this map", "Resize this map", "Free-hand mode",
                  "Effects", "Make a conveyor belt") if $map;
  my $cmd = $ui->choose(-escapable => 1, -idx => 1, "Yes, my liege?", @choices);
  return unless defined($cmd);
  if ($cmd == 0) {
    # Open
    before_change();
    # Ffff when did I sign up to write a file browser
    my $file = "../../saved_maps/";
    while (1) {
      msg see => "pwd $file";
      my @ls = (glob("$file*"), "..");
      if (@ls) {
        $file = $ui->choose("Open which map?", @ls);
        if ($file =~ m/\.map$/) {
          open_map($file);
          last;
        } else {
          $file .= "/";
        }
      } else {
        $ui->popup("You have no saved maps yet");
        last;
      }
    }
  } elsif ($cmd == 1) {
    # New
    before_change();
    undef $fn;
    my ($h, $w) = get_size();
    if ($ui->choose(-idx => 1, "What to start with?", "Blank map", "Blank with borders")) {
      $map = BDSM::Map->new($h, $w, ".");
      $map->border;
      $map->fill([1, 1], [$h - 1, $w - 1], " ");
    } else {
      $map = BDSM::Map->new($h, $w, " ");
    }
    open_map($map);
  } elsif ($cmd == 2) {
    before_change();
    exit;
  } elsif ($cmd == 3) {
    save_map();
  } elsif ($cmd == 4) {
    # Resize
    my ($h, $w) = get_size();
    my $dy = $h - $map->height;
    my $dx = $w - $map->width;
    if ($dy < 0 or $dx < 0) {
      return if $ui->choose(-idx => 1, "This'll nuke part of the map", "That's fine", "Oops, never mind");
    }

    if ($dy < 0) {
      splice @{ $map->{Map} }, $h + 1, abs($dy);
    } elsif ($dy > 0) {
      foreach my $y ($map->height + 1 .. $h) {
        foreach my $x (0 .. $map->width) {
          $map->{Map}[$y][$x] ||= { _ => "?" };
        }
      }
    }

    my $oldw = $map->width;
    foreach my $y (0 .. $map->height) {
      if ($dx < 0) {
        splice @{ $map->{Map}[$y] }, $w + 1, abs($dx);
      } elsif ($dx > 0) {
        foreach my $x ($oldw + 1 .. $w) {
          $map->{Map}[$y][$x] = { _ => "?" };
        }
      }
    }
    open_map($map);
  } elsif ($cmd == 5) {
    # Freehand
    $ui->popup(-size => [4, 46], "Move your cursor and start typing to draw. Switch back to normal mode by pressing TAB.");
    $freehand = 1;
  } elsif ($cmd == 6) {
    effects_menu();
  } elsif ($cmd == 7) {
    # Conveyor
    $ui->popup("Make sure there's room for a length 3 starting at your cursor.");
    my $dir = $ui->choose("What direction?", qw(n s w e nw ne sw se));
    my $belt = BDSM::Toy::Conveyor->new($map, -at => [$start_y, $start_x], -dir => $dir, -length => 3);
    UI->_startbelt($belt) if $belt;
  }
}

sub before_change {
  return unless $map;
  save_map() if $ui->choose("Save current map first?", "Yeah", "Nah") eq "Yeah";
}

sub open_map {
  my $in = shift;

  # Nuke old effects
  GAME->unschedule(-tags => ["map"]);
  $ui->clean_fx if $map;

  if (ref $in and $in->isa("BDSM::Map")) {
    $map = $in;
  } else {
    $map = bless { Map => [], Agents => {}, Rectangles => {}, Toys => {} }, "BDSM::Map";
    $map->hook(BeltWhipper => $before_toy, sub {
      shift;
      my $heap = shift;
      return unless shift eq "mod";
      my ($y, $x, $old) = @_;
      return unless $old; # Only direct calls from mod/overmod
      my $new = $map->tile($y, $x);
      return unless my $belt = $new->{Toy};

      # Is it a conveyor belt-related change?
      # if it's in the new and we don't have that belt/y/x combo stored yet, handle it.
      return if $heap->{$belt}{"$y,$x"};
      delete $old->{Toy};  # This means nothing, we put this in early on purpose
      $heap->{$belt}{"$y,$x"} = $old;
    });

    $fn = $in;
    $map->new($in);
  }


  GAME->{Map} = $map;
  $map->{_Data}{superlight} = 1;
  $ui->{Main}->bindmap($map);
  $ui->{Main}->drawme;

  # Turn on effects
  $ui->eyecandy($_) foreach keys %{ $map->{_Data}{Effects} };
}

sub save_map {
  # Before we save, nuke all the belts
  my @belts;
  push @belts, nuke_toy($_) foreach values %{ $map->{Toys}{Conveyors} };

  # Save
  unless ($fn) {
    while (1) {
      my $try = $ui->askfor(-limit => 15, "Filename for your map?") or next;
      $try = "../../saved_maps/$try";
      if (-f $try) {
        $ui->popup("$try already exists, won't overwrite.");
        next;
      }
      $fn = $try;
      last;
    }
  }
  open my $out, ">$fn" or die "Can't write $fn: $!\n";
  print $out $map->_savemap;
  msg see => "$fn saved in the saved_maps directory";

  # And restore
  foreach (@belts) {
    $_->setup($map, @{ $_->{Data} }[1 .. $#{ $_->{Data} }]);
    UI->_startbelt($_);
  }
}

sub get_size {
  my ($h, $w) = ("", "");
  $h = $ui->askfor("Height?") until $h =~ m/^\d+$/ and $h > 0;
  $w = $ui->askfor("Width?")  until $w =~ m/^\d+$/ and $w > 0;
  return ($h - 1, $w - 1);
}

sub set_brush {
  %brush = ();

  my @types = sort (keys %{ CFG->{Tilemap} });
  my $type = $ui->choose(-idx => 1, "Tile type?",
    "Don't set", map { CFG->{Tilemap}{$_}{Name} or "Type $_" } @types
  );
  $brush{type} = $types[$type - 1] if $type;

  if (my $key = $ui->askfor(-limit => 10, "Extra tile data? Key? Usually leave blank")) {
    my $value = $ui->askfor(-limit => 20, "$key = ?");
    $brush{extra} = [$key, $value];
  }

  $brush{symbol} = $ui->askfor(-limit => 1, "Tile symbol? Wossit look like?");

  $brush{color} = $ui->pick_color;

  $brush{color} ||= "grey" if $brush{symbol}; # It'd happen anyway.

  $ui->{Brush}->update(BSymbol => ($brush{symbol} or "none"));
  $ui->{Brush}->update(BColor => ($brush{color} ? "<$brush{color}>$brush{color}" : "none"));
  $ui->{Brush}->update(
    BType => $brush{type} ? (CFG->{Tilemap}{ $brush{type} }{Name} // "Type $_") : "none"
  );
  $ui->{Brush}->update(BExtra => ($brush{extra} ? @{ $brush{extra} } : ("none", "nada")));
}

sub apply_brush {
  my ($y, $x) = @_;
  my $tile = $map->tile($y, $x);
  $tile->{_} = $brush{type} if $brush{type};
  if (my $extra = $brush{extra}) {
    $tile->{ $extra->[0] } = $extra->[1];
  }

  if ($brush{symbol} and $brush{color}) {
    $map->mod($y, $x, symbol => $brush{symbol}, $brush{color});
  } elsif ($brush{color}) {
    my $now = $map->toplayer($y, $x, "symbol");
    if ($now) {
      $map->mod($y, $x, symbol => $now->[1], $brush{color});
    } else {
      $map->mod($y, $x, symbol => " ", $brush{color});
    }
  }
  $map->modded($y, $x);
}

sub clean_stretch {
  if (@oldstretch) {
    foreach my $Y ($oldstretch[0] .. $oldstretch[1]) {
      foreach my $X ($oldstretch[2] .. $oldstretch[3]) {
        $ui->{Main}->_unhighlight($Y, $X);
      }
    }
  }
  @oldstretch = ();
}

mkdir "../../saved_maps";
msg plain => "<cyan>TAB<grey>: menu";
msg plain => "<cyan>BACKSPACE<grey>: edit brush";
msg plain => "<cyan>SPACE<grey>: apply brush";
msg plain => "<cyan>DELETE<grey>: clear tile";
msg plain => "<cyan>/<grey>: stretch brush";
msg plain => "<cyan>F<grey>: floodfill";
msg plain => "<cyan>T<grey>: layer toggle";
msg plain => "<cyan>R<grey>: show brush +";
$ui->{Brush}->update(Header => 42);
$ui->{Brush}->update(BHeader => 42);
$ui->{Brush}->update(BSymbol => "none");
$ui->{Brush}->update(BColor => "none");
$ui->{Brush}->update(BType => "none");
$ui->{Brush}->update(BExtra => "none", "nada");
menu() until $map;
while (1) {
  $ui->{Main}->target(-ref => { Y => $start_y, X => $start_x }, -scroll => 1, -no_quick => 1, -call => sub {
    my (undef, $y, $x, $key) = @_;
    ($start_y, $start_x) = ($y, $x);
    my $tile = $map->tile($y, $x);
    my $act = $ui->key($key);
    if ($act eq "switch_focus" and !$stretch and !$movetoy) {
      undef $stretch; # TODO and clean
      $freehand ? $freehand = 0 : return menu();
    }
    if ($key eq "/" and !$freehand) {
      if ($stretch) {
        undef $stretch;
        foreach my $Y ($oldstretch[0] .. $oldstretch[1]) {
          foreach my $X ($oldstretch[2] .. $oldstretch[3]) {
            apply_brush($Y, $X);
          }
        }
        clean_stretch();
      } else {
        if (%brush) {
          $stretch = [$y, $x];
        } else {
          $ui->popup("Useless to stretch, set a brush first with BACKSPACE");
        }
      }
    }
    if ($key eq "F") {
      if (%brush) {
        my $match = $map->copy($y, $x);
        $map->flood(
          -asap  => 1,
          -from  => [[$y, $x]],
          -dir   => "diag",
          -valid => sub {
            my $tile = shift;
            return if $match->{_} ne $tile->{_};
            my $them = $map->toplayer($tile, "symbol") // ["", ""];
            if (my $sym = $map->toplayer($match, "symbol")) {
              return if !$them or $them->[1] ne $sym->[1] or $them->[2] ne $sym->[2];
            } else {
              return if $them->[0]; # If we have no symbol but they do...
            }
            return 1;
          },
          -each_node => sub {
            my (undef, $Y, $X) = @_;
            # TODO just by type and symbol/color for now
            apply_brush($Y, $X);
            $ui->{Main}->drawme;
          }
        );
      } else {
        $ui->popup("Useless to floodfill, set a brush first with BACKSPACE");
      }
    }

    my @code;
    if ($freehand and length($key) == 1) {
      my $color = $map->toplayer($y, $x, "symbol");
      $color ||= [];
      $map->mod($y, $x, symbol => $key, ($color->[2] // "grey"));
      @code = (":TARGET", $y, $x + 1);
      $code[-1] = $x if $x + 1 > $map->width;
    } elsif ($freehand and $act eq "backspace" and $x > 0) {
      my $color = $map->toplayer($y, $x - 1, "symbol");
      $color ||= [];
      $map->mod($y, $x - 1, symbol => " ", ($color->[2] // "grey"));
      @code = (":TARGET", $y, $x - 1);
    } else {
      # Panning controls
      $ui->{Main}->left  if $key eq "H";
      $ui->{Main}->down  if $key eq "J";
      $ui->{Main}->up    if $key eq "K";
      $ui->{Main}->right if $key eq "L";

      # Change a tile
      %$tile = (_ => " ") if $act eq "delete";
      set_brush()         if $act eq "backspace" and !$freehand;
      apply_brush($y, $x) if $key eq " ";
    }

    if ($movetoy) {
      my $lenmod = 0;
      $lenmod++ if $key eq "+";
      $lenmod-- if $key eq "-";
      # Get rid of it
      nuke_toy($movetoy);
      # Then redraw it
      my @oldpos = $movetoy->orig_at;
      unless ($movetoy->setup($map,
        length => $movetoy->{Len} + $lenmod, dir => $movetoy->{Dir}, at => [$y, $x])
      ) {
        $movetoy->setup($map, length => $movetoy->{Len} - $lenmod, dir => $movetoy->{Dir}, at => \@oldpos)
      }
      UI->_startbelt($movetoy);
      undef $movetoy, $key = "" if $key eq "?"; # Or else we loop :P
      if ($act eq "delete") {
        nuke_toy($movetoy);
        $key = "";
        # And kill the data
        my $ls = $map->{_Data}{Toys};
        @$ls = grep { $movetoy->{Data} != $_ } @$ls;
        undef $movetoy;
      }
    }

    # Discuss the current tile
    $ui->{Brush}->update(At => $y, $x);
    my $sym = $map->toplayer($y, $x, "symbol");
    $sym = $sym ? "<$sym->[2]>$sym->[2] $sym->[1]" : "";
    $ui->{Brush}->update(Tile => $sym);
    $ui->{Brush}->update(Type => CFG->{Tilemap}{ $tile->{_} }{Name} // "Other: $tile->{_}");
    #$ui->{Brush}->update(Extra => $tile->{Feature} // "none"); # TODO how?
    if (!$freehand and !$stretch and !$movetoy) {
      if ($tile->{Toy}) {
        if ($key eq "?") {
          $movetoy = $tile->{Toy};
          @code = (":TARGET", $movetoy->orig_at);
        } else {
          $ui->{Brush}->update(Msg => "Press <cyan>?<grey> to move belt");
        }
      } else {
        $ui->{Brush}->update(Msg => "");
      }
    }

    if ($stretch) {
      clean_stretch();
      my ($y1, $x1) = @$stretch;
      my ($y2, $x2) = ($y, $x);
      ($y1, $y2) = ($y2, $y1) if $y1 > $y2;
      ($x1, $x2) = ($x2, $x1) if $x1 > $x2;
      foreach my $Y ($y1 .. $y2) {
        foreach my $X ($x1 .. $x2) {
          $ui->{Main}->_highlight($Y, $X);
        }
      }
      @oldstretch = ($y1, $y2, $x1, $x2);
    }

    if ($key eq "T") {
      no warnings "redefine";
      if ($layer) {
        *HexedUI::Hexed::Map::render = $layer;
        undef $layer;
      } else {
        $layer = \&HexedUI::Hexed::Map::render;
        *HexedUI::Hexed::Map::render = sub {
          my ($hexed, $tile) = @_;
          my $t = $tile->{_};
          my ($s, $c) = (CFG->{Tilemap}{$t}{Symbol} // $t, CFG->{Tilemap}{$t}{Color});
          my $l = $tile->{Layers}[-1];
          if ($l and $l->[0] == GAME->{BDSMLayers}{hilite}) {
            $c = "$c/white";  # Naive yes but I don't care
          }
          return ($s, $c);
        };
      }
      for my $y (0 .. $map->height) {
        for my $x (0 .. $map->width) {
          $map->modded($y, $x);
        }
      }
    }
    if ($key eq "R" and $brush{extra}) {
      no warnings "redefine";
      if ($layer) {
        *HexedUI::Hexed::Map::render = $layer;
        undef $layer;
      } else {
        $layer = \&HexedUI::Hexed::Map::render;
        my ($key, $val) = @{ $brush{extra} };
        *HexedUI::Hexed::Map::render = sub {
          my ($hexed, $tile) = @_;
          my ($s, $c) = $layer->($hexed, $tile);
          $c = "white/red" if $tile->{$key} and $tile->{$key} eq $val;
          return ($s, $c);
        };
      }
      for my $y (0 .. $map->height) {
        for my $x (0 .. $map->width) {
          $map->modded($y, $x);
        }
      }
    }

    return @code;
  });
}

sub nuke_toy {
  my $toy = shift;
  my $ls = $before_toy->{$toy} // {};
  #die "cant nuke $toy; we dunno map underneath\n" unless my $ls = $before_toy->{$toy};
  while (my ($key, $old) = each %$ls) {
    my ($y, $x) = split(",", $key);
    $map->{Map}[$y][$x] = $old;
    $map->modded($y, $x);
  }
  delete $before_toy->{$toy}; # When we move it, gonna be overwriting much of this
  delete $map->{Toys}{Conveyors}{$toy};
  return $toy;
}

sub effects_menu {
  return unless defined(my $type = $ui->choose(-escapable => 1, -idx => 1, "What effect?",
    "X weave background in the space"
  ));
  if ($type == 0) {
    foreach my $y (0 .. $map->height) {
      foreach my $x (0 .. $map->width) {
        my $tile = $map->tile($y, $x);

        # To clean up this laggy effect
        if (($x % 4 == 1 or $x % 4 == 3) and $tile->{_} eq " " and !$tile->{Belt}) {
          if ($tile->{Layers}[-1] and $tile->{Layers}[-1][1] =~ m#[\\/]#) {
            delete $tile->{Layers};
            $map->modded($y, $x);
          }
        }

        next unless $tile->{_} eq " " and !@{ $tile->{Layers} };
        if ($y % 2) {
          # Odd row
          #$map->mod($y, $x, symbol => "/", "Black") if $x % 4 == 1;
          #$map->mod($y, $x, symbol => "\\", "Black") if $x % 4 == 3;
        } else {
          # Even row
          #$map->mod($y, $x, symbol => "/", "Black") if $x % 4 == 3;
          #$map->mod($y, $x, symbol => "\\", "Black") if $x % 4 == 1;
        }
      }
    }
  }
}
