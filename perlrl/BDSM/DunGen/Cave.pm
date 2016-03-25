package BDSM::DunGen::Cave;

use strict;
use warnings;
use Util;

use BDSM::Map;

# Returns a cave of specified height and width.
sub generate {
  my ($class, $height, $width) = @_;

  my $map = BDSM::Map->new($height, $width, "#");
  # A cave is a random noisemap with cellular automata rules applied.

  # Generate random tiles.
  foreach my $y (1 .. $height - 1) {
    foreach my $x (1 .. $width - 1) {
      $map->{Map}[$y][$x]{_} = percent(50) ? "#" : ".";
    }
  }

  $map->cellular(3);

  return $map;
}

42;
