##################
# Area::Building #
##################

package Roguelike::Area::Building;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Roguelike::Tilemap;
use Roguelike::Area;
use Roguelike::Area::Structure::Room;
use Roguelike::Area::Structure::Hall;

sub generate {
  shift;  # We aren't really a class, no are we?
  my ($height, $width, $depth) = @_;
  my $map = new Roguelike::Tilemap $height, $width, ".";
  # Since we're an area, not a structure, we get a list of data.
  $map->{Exits} = [];
  $map->border;
  # Get rid of those temporary floor tiles used for bordering.
  $map->fill([1, 1], [$height - 1, $width - 1], " ");
  # If they want a blank map, they comply.
  if ($depth == 0) {
    $map->refresh;
    return $map;
  }
  # Can't use spawn cause it uses connect. So just manually do first room and
  # hallway set.
  # Place first room
  my $exits = { N => [], S => [], E => [], W => [] };
  my $first = new Roguelike::Area::Structure::Room 10, 15;  # Defaults!
  place($first, on => $map, at => [ int($height / 2), int($width / 2) ]);
  # Get the exit data
  foreach my $dir (qw(N S W E)) {
    foreach (0 .. $#{$first->{Exits}{$dir}}) {
      push @{ $exits->{$dir} }, { ID => 0, Wall => $_ };
    }
  }
  # HALLWAYS!
  my @halls;
  foreach my $dir (qw(N S W E)) {
    foreach (@{ $exits->{$dir} }) {
      my $hall;
      $hall = new Roguelike::Area::Structure::Hall 3, 2
        if $dir eq "N" or $dir eq "S";
      $hall = new Roguelike::Area::Structure::Hall 2, 4
        if $dir eq "W" or $dir eq "E";
      if (&connect
      (
        $hall,
        on => $map,
        to => $_->{ID},
        wall => $_->{Wall},
        dir => $dir,
        aligned => "middle"
      )) {
        push @halls, { ID => $#{ $map->{Exits} }, Wall => 0, Dir => $dir };
      }
    }
  }
  # Now whip out dat recurse thang!
  $depth--;
  if ($depth) {
    foreach (@halls) {
      spawn($map, $_, $depth);
    }
  }
  # Now we make things nicer. If there are two hallways next to each other that
  # could be connected... go for it. Horizontally first... it's just easier.
  # This code is very similar to findwall!
  foreach my $y (1 .. $map->height - 1) { # Make life easier NOW
    my $mode = 0; # 0 = nothing so far   1 = we've got a wall!
    my $x1 = 0;
    my $x2 = 0;
    my $cnt = 0;
    my $id = 0;
    foreach my $x (1 .. $map->width - 1) {
      # I should also do the thing that creates logical connections. Bah. And
      # fix the data structures, harhar.
      if ($map->{Map}[$y - 1][$x]{_} eq " "
               or $map->{Map}[$y + 1][$x]{_} eq " "
              )
      {  # Failure
        $x1 = $x2 = $mode = 0;
      }
      my $tile = $map->{Map}[$y][$x]{_};
      if ($tile eq "." and $mode == 0) {  # Start
        next unless $map->{Map}[$y][$x + 1]{_} eq "#";  # Lookahead
        $x1 = $x;
        $mode = 1;
        $cnt = 0;
        $id = $map->{Map}[$y][$x]{ID};
      } elsif ($tile eq "." and $cnt == 1) { # Stop
        # Wait...
        if ($map->{Map}[$y][$x]{ID} == $id) {
          # GAH
          $x1 = $x2 = $mode = 0;
          next;
        }
        $x2 = $x;
        $mode = 0;
        $cnt = 0;
        $map->fill([$y, $x1], [$y, $x2], ".");
        $x1 = $x2 = 0;
      } elsif ($mode == 1 and $tile ne "#") { # Failure.
        $x1 = $x2 = $mode = 0;
      } elsif ($mode == 1 and $tile eq "#" and $cnt == 0) {
        $cnt = 1;
      }
    }
    # No leftovers, sorry.
  }
  # Now vertically!
  foreach my $x (1 .. $map->width - 1) { # Make life easier NOW
    my $mode = 0; # 0 = nothing so far   1 = we've got a wall!
    my $y1 = 0;
    my $y2 = 0;
    my $cnt = 0;
    my $id = 0;
    foreach my $y (1 .. $map->height - 1) {
      # I should also do the thing that creates logical connections. Bah. And
      # fix the data structures, harhar.
      if ($map->{Map}[$y][$x - 1]{_} eq " "
               or $map->{Map}[$y][$x + 1]{_} eq " "
              )
      {  # Failure
        $y1 = $y2 = $mode = 0;
      }
      my $tile = $map->{Map}[$y][$x]{_};
      if ($tile eq "." and $mode == 0) {  # Start
        next unless $map->{Map}[$y + 1][$x]{_} eq "#";  # Lookahead
        $y1 = $y;
        $mode = 1;
        $cnt = 0;
        $id = $map->{Map}[$y][$x]{ID};
      } elsif ($tile eq "." and $cnt == 1) { # Stop
        # Wait...
        if ($map->{Map}[$y][$x]{ID} == $id) {
          # GAH
          $y1 = $y2 = $mode = 0;
          next;
        }
        $y2 = $y;
        $mode = 0;
        $cnt = 0;
        $map->fill([$y1, $x], [$y2, $x], ".");
        $y1 = $y2 = 0;
      } elsif ($mode == 1 and $tile ne "#") { # Failure.
        $y1 = $y2 = $mode = 0;
      } elsif ($mode == 1 and $tile eq "#" and $cnt == 0) {
        $cnt = 1;
      }
    }
    # No leftovers, sorry.
  }
  transform($map, "#", " ");
  transform($map, ".", "#");
  transform($map, " ", ".");
  # Hotspots!
  $_->{Hotspots} = [] foreach @{ $map->{Exits} };
  foreach (1 .. 50) { # Zzz
    while (1) {
      my $y = random(1, $height);
      my $x = random(1, $width);
      next unless $map->{Map}[$y][$x]{_} eq ".";
      push @{ $map->{Exits}[0]{Hotspots} }, [$y, $x];
      last;
    }
  }
  $map->refresh;
  return $map;
}

sub spawn {
  my $map = shift;
  my $dat = shift;
  my $depth = shift;
  # $dat = { ID => of hall, Wall => 0 (always, duh), Dir => direction }
  # Place room
  my $exits = { N => [], S => [], E => [], W => [] }; # To place halls!
  my $room = new Roguelike::Area::Structure::Room 5, 8;  # Defaults!
  return -1 unless &connect
  (
    $room,
    on => $map,
    to => $dat->{ID},
    wall => 0,  # It's a hallway. No weird shapes.
    dir => $dat->{Dir},
    aligned => "middle"
  );
  # Get the exit data
  foreach my $dir (qw(N S W E)) {
    next if $dir eq opposite($dat->{Dir});  # There's just no point in TRYING
    foreach (0 .. $#{$room->{Exits}{$dir}}) {
      push @{ $exits->{$dir} }, { ID => $#{ $map->{Exits} }, Wall => $_ };
    }
  }
  # Now make hallways.
  my @halls;
  foreach my $dir (qw(N S W E)) {
    foreach (@{ $exits->{$dir} }) {
      my $hall;
      $hall = new Roguelike::Area::Structure::Hall 3, 2
        if $dir eq "N" or $dir eq "S";
      $hall = new Roguelike::Area::Structure::Hall 2, 4
        if $dir eq "W" or $dir eq "E";
      if (&connect
      (
        $hall,
        on => $map,
        to => $_->{ID},
        wall => $_->{Wall},
        dir => $dir,
        aligned => "middle"
      )) {
        push @halls, { ID => $#{ $map->{Exits} }, Dir => $dir };
      }
    }
  }
  # Recurse?
  $depth--;
  if ($depth) {
    foreach (@halls) {
      spawn($map, $_, $depth);
    }
  }
  return 1;
}

42;
