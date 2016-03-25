#!/usr/bin/perl

use strict;
use warnings;
use lib "../../perlrl";
use lib "../..";
use Util;

use BDSM::Map;

# First just get a grid.
die "Need filename\n" unless @ARGV;
my @lines = slurp(shift @ARGV);
my $padw = length($lines[0]); # First line dictates.
my @grid;
foreach (@lines) {
  $_ .= " " x ($padw - length($_));
  push @grid, [split(//, $_)];
}

# Then make it into a map.
my $map = [];
foreach my $y (0 .. $#grid) {
  foreach my $x (0 .. $padw - 1) {
    my $tile = $grid[$y][$x];
    if ($tile eq " " or $tile eq "#" or $tile eq ".") {
      $map->[$y][$x] = { _ => $tile };
    } else {
      $map->[$y][$x] = { _ => " " };
      $map->[$y][$x]{Layers}[0] = [GAME->{BDSMLayers}{symbol}, $tile, "grey"];
    }
  }
}

my $obj = bless { Map => $map }, "BDSM::Map";
print $obj->_savemap;
