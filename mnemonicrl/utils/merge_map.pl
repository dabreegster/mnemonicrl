#!/usr/bin/perl

# Blits the second map on the first with the specified offset. Blindly overwrites

use strict;
use warnings;
use lib "../../";
use lib "../../perlrl";
use Util;

use BDSM::Map;

die "Usage: map1 map2 yoff xoff\n" unless @ARGV == 4;

my $orig = BDSM::Map->new(shift @ARGV);
my $new = BDSM::Map->new(shift @ARGV);
my ($y_off, $x_off) = @ARGV;

# Handle resizing
if ((my $diff = $new->width + $x_off - $orig->width) > 0) {
  foreach my $y (0 .. $orig->height) {
    push @{ $orig->{Map}[$y] }, { _ => " " } for 0 .. $diff;
  }
}
if ((my $diff = $new->height + $y_off - $orig->height) > 0) {
  foreach my $row (0 .. $diff) {
    my $row = [];
    push @$row, { _ => " " } for 0 .. $orig->width;
    push @{ $orig->{Map} }, $row;
  }
}

# Merge
foreach my $y (0 .. $new->height) {
  foreach my $x (0 .. $new->width) {
    $orig->{Map}[$y + $y_off][$x + $x_off] = $new->{Map}[$y][$x];
  }
}

#$orig->_dump(*STDOUT);
open my $out, ">merged.map" or die "Can't write merged.map: $!\n";
print $out $orig->_savemap;
close $out;
print "Wrote merged.map\n";
