package BDSM::DunGen::BoardMaze;

use strict;
use warnings;
use Util;

use BDSM::Map;
use BDSM::Vector;

# Perfect maze algorithm... couldn't be easier, right?
sub generate {
  my ($class, $height, $width) = @_;

  my $maze = BDSM::DunGen::Maze->generate($height, $width);
  my ($h, $w) = (5, 10);
  my $map = BDSM::Map->new((($height + 1) * $h) - 0, (($width + 1) * $w) - 0, " ");

  # Scale everything up
  foreach my $y (0 .. $maze->height) {
    foreach my $x (0 .. $maze->width) {
      next unless $maze->get($y, $x) eq "#";
      $map->fill([$y * $h, $x * $w], [($y + 1) * $h, ($x + 1) * $w], "#");
    }
  }

  # Tiled floor makes it look slightly more like a kitchen, yeah?
  foreach my $y (0 .. $map->height) {
    foreach my $x (0 .. $map->width) {
      next unless $map->get($y, $x) eq "#";
      my $color = ($x + $y) % 2 == 0 ? "grey/red" : "grey/faded";
      $map->mod($y, $x, symbol => " ", $color);
    }
  }

  # Walk the path
  my ($y, $x) = (10, 13);
  for (1 .. 200) {
    debug "iter $_";
    my @next = grep {
      $map->stfucheck(@$_) and $map->get(@$_) ne "." and clear($map, @$_)
    } adjacent_tiles("diag", $y, $x);
    # Mod after we search to simplify things
    $map->mod($y, $x, ".");
    $map->mod($y, $x, symbol => ".", "grey");
    last unless @next;
    ($y, $x) = @{ choosernd(@next) };
  }

  $map->{_Data}{$_} = 1 for qw(empty superlight nostairs);
  return $map;
}

# Does a tile have any other path tiles by it?
sub clear {
  my $map = shift;
  return scalar(grep {
    $map->stfucheck(@$_) and $map->get(@$_) eq "."
  } adjacent_tiles("diag", @_)) == 0;
}

42;
