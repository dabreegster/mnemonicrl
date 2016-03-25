##################
# Area::Cellular #
##################

package Roguelike::Area::Cellular;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Roguelike::Tilemap;
use Roguelike::Area;

sub generate {
  shift;  # We aren't really a class, no are we?
  my $height = shift;
  my $width = shift;
  my $fill = shift;
  my $map = new Roguelike::Tilemap $height, $width, "#";
  # Generate random tiles.
  foreach my $y (1 .. $height - 1) {
    foreach my $x (1 .. $width - 1) {
      # Screw my awesome probability utils!
      $map->{Map}[$y][$x]{_} = rand() < 1 / 3 ? "#" : ".";
    }
  }
  # Then run the cellular automata algorithm over it.
  cellular($map, 3);
  # Invert. :(
  transform($map, " ", ".");
  # Hotspots!
  $map->{Exits}[0]{Hotspots} = [];
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

42;
