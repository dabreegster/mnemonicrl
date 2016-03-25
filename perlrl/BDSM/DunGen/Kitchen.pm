package BDSM::DunGen::Kitchen;

use strict;
use warnings;
use Util;

use BDSM::Map;
use BDSM::DunGen::Shape;

# Perfect maze algorithm... couldn't be easier, right?
sub generate {
  my ($class, $height, $width) = @_;

  # Transform it into a maze... of stovetops!!
  my $stove = BDSM::DunGen::Shape->new("content/hotel/stove.map");
  my $horiz = BDSM::DunGen::Shape->new("content/hotel/stove_horiz.map");
  my $vert = BDSM::DunGen::Shape->new("content/hotel/stove_vert.map");
  my ($h, $w) = ($stove->height + 1, $stove->width + 1);
  my $maze = BDSM::DunGen::Maze->generate($height, $width);
  my $map = BDSM::Map->new((($height + 1) * $h) - 1, (($width + 1) * $w) - 1, " ");

  my @spawns;

  foreach my $y (0 .. $maze->height) {
    foreach my $x (0 .. $maze->width) {
      next unless $maze->get($y, $x) eq "#";
      $stove->place(on => $map, at => [$y * $h, $x * $w], mergeblit => 1);
      push @spawns, [($y * $h) + 2, ($x * $w) + 3];

      my $dn = ($y != 0 and $maze->get($y - 1, $x) eq "#");
      my $ds = ($y != $maze->height and $maze->get($y + 1, $x) eq "#");
      my $dw = ($x != 0 and $maze->get($y, $x - 1) eq "#");
      my $de = ($x != $maze->width and $maze->get($y, $x + 1) eq "#");

      $vert->place(on => $map, at => [(($y + 1) * $h) - 1, $x * $w], forceblit => 1) if $ds;
      # Horiz last because of the way intersections work
      $horiz->place(on => $map, at => [$y * $h, (($x + 1) * $w) - 1], forceblit => 1) if $de;
      # Special case, I dunno how else to fix this :|
      $map->mod(($y * $h) + $h - 1, $x * $w, symbol => ".", "grey") if $ds and $dw;

      # Clear out a corridor to make the path.
      $map->mod(($y * $h) + 2, ($x * $w) + 1, ".") if $dw;
      $map->mod(($y * $h) + 2, ($x * $w) + 2, ".") if $dw;

      $map->mod(($y * $h) + 2, ($x * $w) + 4, ".") if $de;
      $map->mod(($y * $h) + 2, ($x * $w) + 5, ".") if $de;

      $map->mod(($y * $h) + 1, ($x * $w) + 3, ".") if $dn;
    }
  }

  # Tiled floor makes it look slightly more like a kitchen, yeah?
  foreach my $y (0 .. $map->height) {
    foreach my $x (0 .. $map->width) {
      next unless $map->get($y, $x) eq " ";
      my $color = ($x + $y) % 2 == 0 ? "grey" : "grey/faded";
      $map->mod($y, $x, symbol => " ", $color);
    }
  }

  @spawns = shuffle(@spawns);

  # Make a few pots...
  for (1 .. CFG->{Hotel}{Pots}) {
    $map->mod(@{ shift @spawns }, symbol => "U", "yellow/faded");
  }

  # And the ingredients...
  for (1 .. CFG->{Hotel}{Ingredients}) {
    GAME->make("Ingredient",
      Map => $map,
      At  => shift @spawns
    ) unless GAME->{NoDiffuse};
  }

  $map->{_Data}{$_} = 1 for qw(empty superlight nostairs);
  $map->{_Data}{mvlag} = 0.05;
  $map->{Depth} = "Kitchen";

  $map->mod(5, 9, symbol => "<", ">", "Red");
  $map->stair(5, 9, "Hotel_Atrium", "kitchen");

  $map->{spawnpt}{atrium} = [];
  for my $y (4 .. 6) {
    for my $x (7 .. 11) {
      $map->tile($y, $x)->{spawnpt} = "atrium";
      push @{ $map->{spawnpt}{atrium} }, [$y, $x];
    }
  }
  return $map;
}

42;
