package BDSM::Vector;

use strict;
use warnings;
use Util;

use Exporter;
our @ISA = ("Exporter");
our @EXPORT = qw(north_of south_of west_of east_of northwest_of northeast_of southwest_of
                 southeast_of dir_of adjacent_tiles euclid dir_relative dir_vert dir_horiz
                 opposite_dir
                );

# These return coordinates relative to an arbitrary object.

sub north_of {
  my $obj = shift;
  ($obj->{Y} - 1, $obj->{X});
}

sub south_of {
  my $obj = shift;
  ($obj->{Y} + 1, $obj->{X});
}

sub west_of {
  my $obj = shift;
  ($obj->{Y}, $obj->{X} - 1);
}

sub east_of {
  my $obj = shift;
  ($obj->{Y}, $obj->{X} + 1);
}

sub northwest_of {
  my $obj = shift;
  ($obj->{Y} - 1, $obj->{X} - 1);
}

sub northeast_of {
  my $obj = shift;
  ($obj->{Y} - 1, $obj->{X} + 1);
}

sub southwest_of {
  my $obj = shift;
  ($obj->{Y} + 1, $obj->{X} - 1);
}

sub southeast_of {
  my $obj = shift;
  ($obj->{Y} + 1, $obj->{X} + 1);
}

# What direction is it from 'from' to 'to'? We're only reliable for one-move-away's.
sub dir_of {
  my %args = @_;
  my ($y1, $x1, $y2, $x2) = (@{ $args{from} }, @{ $args{to} });
  return "northwest" if $y1 > $y2 and $x1 > $x2;
  return "northeast" if $y1 > $y2 and $x1 < $x2;
  return "southwest" if $y1 < $y2 and $x1 > $x2;
  return "southeast" if $y1 < $y2 and $x1 < $x2;
  return "north"     if $y1 > $y2;
  return "south"     if $y1 < $y2;
  return "west"      if $x1 > $x2;
  return "east"      if $x1 < $x2;
  debug "dir_of from $y1, $x1 to $y2, $x2... same coords. O_O why?";  # TODO: Lag?
}

# Return all adjacent tiles of a coordinate.
sub adjacent_tiles {
  unless (@_ == 3) {
    debug [caller];
    die "adjacent_tiles wants 3 args\n";
  }
  my ($which, $y, $x) = @_;
  my @ls;

  push @ls, [$y - 1, $x];
  push @ls, [$y, $x - 1];
  push @ls, [$y, $x + 1];
  push @ls, [$y + 1, $x];

  if ($which eq "diag") {
    push @ls, [$y - 1, $x - 1];
    push @ls, [$y - 1, $x + 1];
    push @ls, [$y + 1, $x - 1];
    push @ls, [$y + 1, $x + 1];
  }

  return @ls;
}

# Euclidean distance
sub euclid {
  my ($y1, $x1, $y2, $x2) = @_;
  return sqrt(($y1 - $y2) ** 2 + ($x1 - $x2) ** 2);
} 

# Badly named... return the coordinates in that direction
sub dir_relative {
  my ($dir, $y, $x) = @_;
  $y-- if $dir eq "north";
  $y++ if $dir eq "south";
  $x-- if $dir eq "west";
  $x++ if $dir eq "east";
  $y--, $x-- if $dir eq "northwest";
  $y--, $x++ if $dir eq "northeast";
  $y++, $x-- if $dir eq "southwest";
  $y++, $x++ if $dir eq "southeast";
  return ($y, $x);
}

# Is the direction vertical? (Orthogonals only!)
sub dir_vert {
  my $dir = shift;
  return 1 if $dir eq "north" or $dir eq "south";
}

# Is the direction horizontal? (Orthogonals only!)
sub dir_horiz {
  my $dir = shift;
  return 1 if $dir eq "west" or $dir eq "east";
}

# Return the direction + 180 degrees.. oh wait, no fun real vector stuff. :(
sub opposite_dir {
  return {
    north     => "south",
    south     => "north",
    west      => "east",
    east      => "west",
    northwest => "southeast",
    southeast => "northwest",
    northeast => "southwest",
    southwest => "northeast",

    n  => "s",
    s  => "n",
    w  => "e",
    e  => "w",
    nw => "se",
    ne => "sw",
    sw => "ne",
    se => "nw",
  }->{ shift() };
}

42;
