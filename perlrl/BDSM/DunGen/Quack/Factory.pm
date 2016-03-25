package BDSM::DunGen::Factory;

use strict;
use warnings;
use Util;

use BDSM::Toy::Conveyor;

sub generate {
  my ($class, $height, $width) = @_;

  my $map = BDSM::Map->new($height, $width, ".");
  $map->border;

  BDSM::Toy::Conveyor->new($map, -at => [7, 5],  -length => 10, -dir => "s");
  BDSM::Toy::Conveyor->new($map, -at => [19, 7], -length => 10, -dir => "e");
  BDSM::Toy::Conveyor->new($map, -at => [7, 17], -length => 10, -dir => "n");
  BDSM::Toy::Conveyor->new($map, -at => [3, 7],  -length => 10, -dir => "w");

  BDSM::Toy::Conveyor->new($map, -at => [10, 25], -length => 3, -dir => "sw");
  BDSM::Toy::Conveyor->new($map, -at => [10, 33], -length => 3, -dir => "se");
  BDSM::Toy::Conveyor->new($map, -at => [15, 25], -length => 3, -dir => "nw");
  BDSM::Toy::Conveyor->new($map, -at => [15, 33], -length => 3, -dir => "ne");

  $map->{_Data}{$_} = 1 for qw(empty superlight nostairs);

  return $map;
}

42;
