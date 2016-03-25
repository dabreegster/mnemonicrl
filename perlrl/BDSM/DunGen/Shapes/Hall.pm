package BDSM::DunGen::Shapes::Hall;

use strict;
use warnings;
use Util;

use BDSM::DunGen::Shape;
our @ISA = ("BDSM::DunGen::Shape");

# Make a new rectangular hallway.
sub orthog {
  my (undef, $height, $width) = @_;

  my $map = BDSM::DunGen::Shape->new($height, $width, ".");
  $map->border;
  $map->findwalls(0, 0, 0, 0);  # Because we're boring.

  return $map;
}

42;
