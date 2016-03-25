package BDSM::DunGen::Test;

use base "BDSM::Map";

use strict;
use warnings;
use Util;

sub generate {
  my ($class, $height, $width) = @_;
  ($height, $width) = (20, 40);
  my $map = $class->new($height, $width, "~");

  $map->fill([10, 10], [10, 20], "#");

  $map->{_Data}{$_} = 1 for qw(empty superlight nostairs);
  $map->{_Data}{Effects} = { ripples => 1 };
  return $map;
}

42;
