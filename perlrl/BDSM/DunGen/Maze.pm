package BDSM::DunGen::Maze;

use strict;
use warnings;
use Util;

use BDSM::Map;
use BDSM::Vector;

# Perfect maze algorithm... couldn't be easier, right?
sub generate {
  my ($class, $height, $width) = @_;

  my $map = BDSM::Map->new($height, $width, "#");
  my @stack;

  # Generate a perfect maze
  my ($cur_y, $cur_x) = (1, 1);
  push @stack, [$cur_y, $cur_x];
  while (@stack) {
    my $found = 0;
    foreach my $dir (shuffle(qw(north south west east))) {
      my ($y1, $x1) = dir_relative($dir, $cur_y, $cur_x);
      my ($y2, $x2) = dir_relative($dir, $y1, $x1);
      next unless $map->stfucheck($y2, $x2) and $map->get($y2, $x2) eq "#";
      $found = 1;
      $map->mod($y1, $x1, ".");
      $map->mod($y2, $x2, ".");
      push @stack, [$y2, $x2];
    }
    unless ($found) {
      ($cur_y, $cur_x) = @{ pop @stack };
    }
  }

  $map->{_Data}{$_} = 1 for qw(empty superlight nostairs);
  return $map;
}

42;
