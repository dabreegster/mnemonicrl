###########
# Tilemap #
###########

package Roguelike::Tilemap;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Roguelike::Container;

sub new {
  my $class = shift;
  my $map = [];
  if (ref $_[0] eq "ARRAY") {
    $map = shift;
  } else {
    my $height = shift;
    my $width = shift;
    my $tile = shift || " ";
    foreach my $y (0 .. $height) {
      foreach my $x (0 .. $width) {
        $map->[$y][$x] = {
          _    => $tile,
          Char => undef,
        };
        $map->[$y][$x]{Inv} = new Roguelike::Container 0, $map->[$y][$x];
      }
    }
  }
  return bless { Map => $map }, $class;
}

sub refresh {
  my $self = shift;
  foreach my $y (0 .. $self->height) {
    foreach my $x (0 .. $self->width) {
      render($self->{Map}[$y][$x]);
    }
  }
}

sub height {
  my $self = shift;
  return $#{ $self->{Map} };
}

sub width {
  my $self = shift;
  return $#{ $self->{Map}[0] }; # We assume every row is equal in width.
}

sub select {
  my ($self, $y1, $x1, $y2, $x2) = @_;
  my @rows;
  foreach my $y ($y1 .. $y2) {
    my $cols = [];
    foreach my $x ($x1 .. $x2) {
      push @{ $cols }, $self->{Map}[$y][$x];
    }
    push @rows, $cols;
  }
  return @rows;
}

sub los_creatures {
}

sub fill {
  my $self = shift;
  my $from = shift;
  my ($y1, $x1) = @$from;
  my $to = shift;
  my ($y2, $x2) = @$to;
  my $tile = shift;
  my $nc = shift;
  my $color = shift;
  # Reversify the coordinates if they need reversifying.
  ($y1, $y2) = ($y2, $y1) if $y2 < $y1;
  ($x1, $x2) = ($x2, $x1) if $x2 < $x1;
  foreach my $y ($y1 .. $y2) {
    foreach my $x ($x1 .. $x2) {
      return 1 if $nc and $self->{Map}[$y][$x]{_} ne " ";
      $self->{Map}[$y][$x]{_} = $tile;
      $self->{Map}[$y][$x]{Color} = $color if $color;
    }
  }
  return 1;
}

sub border {
  # Here be dragons...
  my $self = shift;
  my $map = $self->{Map};
  my $cnty = 0;
  foreach my $y (0 .. $self->height) {
    my $cntx = 0;
    foreach my $x (0 .. $self->width) {
      $map->[$y][$x]{_} = "#"
      if
        $y != 0
      and
        $map->[$y - 1][$x]{_} eq "."
      and
        $map->[$y][$x]{_} eq " ";
      $map->[$y][$x]{_} = "#"
      if
        $y != 0
      and
        $x != 0
      and
        $map->[$y - 1][$x - 1]{_} eq "."
      and
        $map->[$y][$x]{_} eq " ";
      $map->[$y][$x]{_} = "#"
      if
        $y != 0
      and
        defined $map->[$y - 1][$x + 1]
      and
        $map->[$y - 1][$x + 1]{_} eq "."
      and
        $map->[$y][$x]{_} eq " ";
      next unless $map->[$y][$x]{_} eq ".";
      $map->[$y][$x]{_} = "#" if $cnty == 0 or $cntx == 0;
      $map->[$y][$x]{_} = "#" if $y != 0 and $map->[$y - 1][$x]{_} eq " ";
      $map->[$y][$x]{_} = "#" if $x != 0 and $map->[$y][$x - 1]{_} eq " ";
      $map->[$y][$x]{_} = "#"
      if
        defined $map->[$y][$x + 1]
      and
        $map->[$y][$x + 1]{_} eq " ";
      $map->[$y][$x]{_} = "#"
      if
        $y != 0
      and
        $x != 0
      and
        $map->[$y - 1][$x - 1]{_} eq " ";
      $map->[$y][$x]{_} = "#"
      if
        $y != 0
      and
        defined $map->[$y - 1][$x + 1]
      and
        $map->[$y - 1][$x + 1]{_} eq " ";
      $map->[$y][$x]{_} = "#" if $cnty == $self->height;
      $cntx++;
    }
    $map->[$y][-1]{_} = "#" if $map->[$y][-1]{_} eq ".";
    $cnty++;
  }
  return 1;
}

sub row {
  my $self = shift;
  my $y = shift;
  return @{$self->{Map}[$y]};
}

sub column {
  my $self = shift;
  my $x = shift;
  my @columns;
  push @columns, $self->{Map}[$_][$x] foreach (0 .. $self->height);
  return @columns;
}

sub barrier {
  my ($self, $y, $x) = @_;
  return $Game->{UI}{Tiles}{ $self->{Map}[$y][$x]{_} }{Barrier} ? 1 : 0;
}

sub trace {
  my $self = shift;
  my $z = shift;
  my $y = shift;
  my $x = shift;
  my $dir = shift;
  my $more = shift;
  # We could possibly end up going out of player's LOS, but oh well.
  my $map = $Game->{Levels}[$z];
  my @list;
  while (1) {
    $y-- if $dir eq "k";
    $y++ if $dir eq "j";
    $x-- if $dir eq "h";
    $x++ if $dir eq "l";
    $y--, $x-- if $dir eq "y";
    $y--, $x++ if $dir eq "u";
    $y++, $x-- if $dir eq "b";
    $y++, $x++ if $dir eq "n";
    # What do we have here?
    my $tile = $map->{Map}[$y][$x];
    if ($tile->{Char}) {
      push @list, $tile->{Char};
      last unless $more;
    } elsif ($map->barrier($y, $x)) {
      last;
    }
  }
  return @list;
}

42;
