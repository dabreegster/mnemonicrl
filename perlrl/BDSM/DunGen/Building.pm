package BDSM::DunGen::Building;

use strict;
use warnings;
use Util;

use BDSM::Map;
use BDSM::Toy::Conveyor;

sub generate {
  my ($class, $iheight, $iwidth) = @_;

  my $map = BDSM::Map->new($iheight, $iwidth, ".");
  $map->border;

  #divide($map, 1, 1, $iheight - 1, $iwidth - 1, "horiz");
  divide_halls($map, 1, 1, $iheight - 1, $iwidth - 1, "horiz");

  return $map;
}

# TODO: make the roomsizes small, and this thing blows up horribly

sub divide {
  my ($map, $y1, $x1, $y2, $x2, $dir) = @_;

  if ($dir eq "horiz") {
    my $y;
    while (1) {
      $y = random($y1 + .3 * ($y2 - $y1), $y2 - .3 * ($y2 - $y1));
      last if $map->get($y, $x1 - 1) ne "+" and $map->get($y, $x2 + 1) ne "+";
    }
    $map->fill([$y, $x1], [$y, $x2], "#");

    $map->mod($y, random($x1 + 1, $x2 - 1), "+"); # Not on the edges

    return if $x2 - $x1 < 10;
    divide($map, $y1, $x1, $y - 1, $x2, "vert");
    divide($map, $y + 1, $x1, $y2, $x2, "vert");
  } else {
    my $x;
    while (1) {
      $x = random($x1 + .3 * ($x2 - $x1), $x2 - .3 * ($x2 - $x1));
      last if $map->get($y1 - 1, $x) ne "+" and $map->get($y2 + 1, $x) ne "+";
    }
    $map->fill([$y1, $x], [$y2, $x], "#");

    $map->mod(random($y1 + 1, $y2 - 1), $x, "+"); # Not on the edges

    return if $y2 - $y1 < 10;
    divide($map, $y1, $x1, $y2, $x - 1, "horiz");
    divide($map, $y1, $x + 1, $y2, $x2, "horiz");
  }
}

# This version just makes proper corridors
sub divide_halls {
  my ($map, $y1, $x1, $y2, $x2, $dir) = @_;

  if ($dir eq "horiz") {
    my $y;
    while (1) {
      $y = random($y1 + .3 * ($y2 - $y1), $y2 - .3 * ($y2 - $y1));
      last if $map->get($y, $x1 - 1) ne "+" and $map->get($y, $x2 + 1) ne "+";
      last if $map->get($y + 2, $x1 - 1) ne "+" and $map->get($y + 2, $x2 + 1) ne "+";
    }
    $map->fill([$y, $x1], [$y, $x2], "#");
    $map->fill([$y + 2, $x1], [$y + 2, $x2], "#");

    $map->mod($y, random($x1 + 1, $x2 - 1), "+"); # Not on the edges
    $map->mod($y + 2, random($x1 + 1, $x2 - 1), "+"); # Not on the edges

    return if $x2 - $x1 < 10;
    divide_halls($map, $y1, $x1, $y - 1, $x2, "vert");
    divide_halls($map, $y + 3, $x1, $y2, $x2, "vert");
  } else {
    my $x;
    while (1) {
      $x = random($x1 + .3 * ($x2 - $x1), $x2 - .3 * ($x2 - $x1));
      last if $map->get($y1 - 1, $x) ne "+" and $map->get($y2 + 1, $x) ne "+";
      last if $map->get($y1 - 1, $x + 2) ne "+" and $map->get($y2 + 1, $x + 2) ne "+";
    }
    $map->fill([$y1, $x], [$y2, $x], "#");
    $map->fill([$y1, $x + 2], [$y2, $x + 2], "#");

    $map->mod(random($y1 + 1, $y2 - 1), $x, "+"); # Not on the edges
    $map->mod(random($y1 + 1, $y2 - 1), $x + 2, "+"); # Not on the edges

    return if $y2 - $y1 < 10;
    divide_halls($map, $y1, $x1, $y2, $x - 1, "horiz");
    divide_halls($map, $y1, $x + 3, $y2, $x2, "horiz");
  }
}

42;
