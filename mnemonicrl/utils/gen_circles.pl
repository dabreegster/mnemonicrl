#!/usr/bin/perl

# Generates circles inside one another. Useful for the hotel's overworld

use strict;
use warnings;
use lib "../../";
use lib "../../perlrl";
use Util;

use BDSM::Map;

# I've just kind of observed these, can't find the pattern yet
my @radii = ([4, 1]);
#my @radii = ([6, 1], [20, 2], [35, 2], [50, 2]);
#my @radii = ([25, 2]);
my $maxr = $radii[-1]->[0] + 10;  # Generally want to make this larger than the real to have room for padding

my $map = BDSM::Map->new((2 * $maxr) + 0, (4 * $maxr) + 0, " ");

my ($center_x, $center_y) = ($maxr, $maxr);

sub circle {
  my ($r, $pad) = @_;

  # Random artifact if we go 0 .. 360 even though they're the same... oh well
  foreach my $theta (1 .. 360) {
    my $rad = $theta * 3.14159 / 180;
    my $x = int($r * cos($rad) + $center_x);
    my $y = int($r * sin($rad) + $center_y);
    $map->mod($y, $x*2, ".");
    $map->mod($y, $x*2 + 1, ".");

    # Pad the circles so border works better
    #for my $factor (1 .. $pad) {
    #  $map->mod($y - $factor, $x, ".") unless $y - $factor < 0;
    #  $map->mod($y + $factor, $x, ".") unless $y + $factor > $map->height;
    #  $map->mod($y, $x - $factor, ".") unless $x - $factor < 0;
    #  $map->mod($y, $x + $factor, ".") unless $x + $factor > $map->width;
    #}
  }
}

my $cnt = 0;
foreach (@radii) {
  circle(@{ $radii[$cnt] });
  $cnt++;
}

#$map->border;
$map->_dump(*STDOUT);
