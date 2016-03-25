package BDSM::DunGen::Dungeon;

use strict;
use warnings;
use Util;

use BDSM::Vector;
use BDSM::Map;

use BDSM::DunGen::Shapes::Hall;
use BDSM::DunGen::Shapes::Room;

# Returns a room/hall-filled dungeon of specified height and width.
sub generate {
  my ($class, $height, $width) = @_;

  my $map = BDSM::Map->new($height, $width, ".");
  $map->border;
  $map->fill([1, 1], [$height - 1, $width - 1], " ");
  $map->{Shapes} = [];

  my @dead = _spawn($map, { First => 1 }, 10);
  # Connect dead-ends
  # TODO: do we want to shuffle or not? if we dont then maybe ones close together will
  # connect!
  while (@dead > 1) {
    debug $#dead;
    my $one = shift @dead;
    my $oneshape = $map->{Shapes}[ $one->{ID} ];
    my ($y1, $x1) = $oneshape->spawnwall($one->{Dir}, $map);
    # Something may have merged into this deadend, so check first
    next unless $y1 and $map->{Map}[$y1][$x1]{_} eq " ";
    # Instead of randomly pairing deadends and repeatedly failing, try to pair
    # $one with any and all. If they all fail, consider stretching it.
    foreach (0 .. $#dead) {
      #debug " $_ / $#dead";
      my $two = $dead[$_];
      my $twoshape = $map->{Shapes}[ $two->{ID} ];
      my ($y2, $x2) = $twoshape->spawnwall($two->{Dir}, $map);
      next unless $y2 and $map->{Map}[$y2][$x2]{_} eq " ";  # Other end has to be clear too
      if (my @path = $map->pathfind(choosernd("diag", "orthog"), $y1, $x1, $y2, $x2)) {
        _carvepath($map, @path);
        splice(@dead, $_, 1);   # Rid @dead of $two since it's now used
        last;
      }
    }
  }

  # Delete dungeon generation data
  delete $map->{Shapes};
  foreach my $y (0 .. $map->height) {
    foreach my $x (0 .. $map->width) {
      delete $map->{Map}[$y][$x]{ID};
    }
  }
  # The final postprocessing stage: if we've drawn adjacent halls, clear them out for even
  # weirder shapes!
  $map->excavate;

  # Let's make cheap 3D dungeons!
  #$map->{OtherLayer} = _make_layer($map);

  return $map;
}

# Given a room, spawn hallways off it and recurse.
sub _spawn {
  my ($map, $dat, $depth) = @_;
  my @dead;

  # Gimme a room!
  my $room = BDSM::DunGen::Shapes::Room->room(random(10, 15), random(15, 25));
  if ($dat->{First}) {
    $room->place(
      on => $map,
      at => [ $map->height / 2 - $room->height, $map->width / 2 - $room->width ]
    ) or die "Whoa, first room place failed. Small map?\n";
  } else {
    # Connect to the specified exit
    $room->jigsaw(
      on        => $map,
      to_wall   => 0,   # Halls only have one wall per side
      from_wall => random($#{ $room->{Exits}{ opposite_dir($dat->{dir}) } }),
      align     => "middle",
      to        => $dat->{to},   # shape ID
      dir       => $dat->{dir}
    ) or return {   # Aww, a dead-end!
      ID => $dat->{to}, Dir => $dat->{dir},
    };
  }

  # Build all halls then recurse.
  my @spawn;

  # Branch hallways off of every wall
  foreach my $dir ("north", "south", "west", "east") {
    foreach my $wall (0 .. $#{ $room->{Exits}{$dir} }) {
      my $hall = BDSM::DunGen::Shapes::Hall->orthog(
        dir_vert($dir) ? (random(10, 15), random(3, 6)) : (random(3, 6), random(10, 15))
      );
      $hall->jigsaw(
        on        => $map,
        to        => $room->{ID},
        dir       => $dir,
        to_wall   => $wall,
        from_wall => 0,     # Halls only have one wall on each side
        align     => "middle"
      ) and push @spawn, { to => $#{ $map->{Shapes} }, dir => $dir };
    }
  }

  # Recurse?
  if (--$depth) {
    push(@dead, _spawn($map, $_, $depth)) foreach @spawn;
  } else {
    # The useless hallways are also deadends I guess
    push @dead, {
      ID => $_->{to}, Dir => $_->{dir},                        
    } foreach @spawn;
  }
  return @dead;   # And it magically all goes back!
}

# Draw a twisty corridor along a path to connect stuff.
sub _carvepath {
  my ($map, @path) = @_;
  foreach my $step (@path) {
    my ($y, $x) = @$step;
    $map->{Map}[$y][$x]{_} = ".";
    # Put up some walls, hmm?
    foreach my $dir (adjacent_tiles("diag", @$step)) {
      ($y, $x) = @$dir;
      #next if $y < 0 or $y > $map->height or $x < 0 or $x > $map->width;
      $map->{Map}[$y][$x]{_} = "#" if $map->{Map}[$y][$x]{_} eq " ";
    }                                                                     
  }                                                                       
}

# Invert a map to create a 3D 'upper layer'
sub _make_layer {
  my $lower = shift;

  my $upper = BDSM::Map->new($lower->height, $lower->width, " ");
  foreach my $y (0 .. $upper->height) {
    foreach my $x (0 .. $upper->width) {
      my $tile = $lower->get($y, $x) eq " " ? "." : " ";
      $upper->{Map}[$y][$x]{_} = $tile;
    }
  }

  # Kill space too small to be a room
  # Horizontal
  foreach my $y (0 .. $upper->height) {
    my $x1;
    foreach my $x (0 .. $upper->width) {
      if (defined($x1) and ($upper->get($y, $x) eq " " or $x == $upper->width)) {
        $upper->fill([$y, $x1], [$y, $x], " ") if $x - $x1 < 3;
        undef $x1;
      } elsif (defined($x1)) {
      } else {
        next unless $upper->get($y, $x) eq ".";
        $x1 = $x;
      }
    }
  }
  # Vertical
  foreach my $x (0 .. $upper->width) {
    my $y1;
    foreach my $y (0 .. $upper->height) {                                   
      if (defined($y1) and ($upper->get($y, $x) eq " " or $y == $upper->height)) {
        $upper->fill([$y1, $x], [$y, $x], " ") if $y - $y1 < 3;
        undef $y1;
      } elsif (defined($y1)) {
      } else {
        next unless $upper->get($y, $x) eq ".";
        $y1 = $y;
      }
    }
  }

  $upper->border;
  return $upper->{Map};
}

42;
