package BDSM::DunGen::Sky;

use strict;
use warnings;
use Util;

# Some mofo ugly code
# TODO: some kind of cellular automata might look better?

use BDSM::DunGen::Shape;
use BDSM::Toy::Conveyor;
use POSIX ("ceil");

sub generate {
  my ($class, $height, $width) = @_;
  ($height, $width) = (10, 15);

  my $map = BDSM::Map->new($height, $width, ".");
  $map->border;
  $map->fill([1, 1], [$height - 1, $width - 1], " ");

  my @clouds;

  my @spawn;
  push @spawn, [$height - 1, int($width / 2)];
  while (my $cloud = shift @spawn) {
    my ($y, $x) = @$cloud;
    next unless $map->get($y, $x) eq " ";   # May have just covered it
    push @clouds, [$y, $x];

    my $avail = 0;
    $avail++ if $map->_get($y - 2, $x - 2) eq " ";
    $avail++ if $map->_get($y - 2, $x + 2) eq " ";

    my $force = 1;
    if ($map->_get($y - 2, $x - 2) eq " " and ($avail == 1 or percent(50))) {
      $force = 0;
      $map->mod($y - 1, $x - 1, "^");
      $map->tile($y - 1, $x - 1)->{left} = 1;
      push @spawn, [$y - 2, $x - 2];
    }
    if ($map->_get($y - 2, $x + 2) eq " " and ($force or percent(50))) {
      $map->mod($y - 1, $x + 1, "^");
      $map->tile($y - 1, $x + 1)->{right} = 1;
      push @spawn, [$y - 2, $x + 2];
    }
    $map->mod($y, $x, "*");
  }
  while ($clouds[0]->[0] >= $height - 3) {
    my $already = shift @clouds;
    $map->tile(@$already)->{linked} = 1;
  }
  @clouds = reverse @clouds;  # Start at the top!

  # Connect the dots, this is a two-way street
  while (my $cloud = shift @clouds) {
    my ($y, $x) = @$cloud;
    next if $map->tile($y, $x)->{linked};
    $map->tile($y, $x)->{tried}++;
    next if $map->tile($y, $x)->{tried} == 5;
    # A* and find out.
    if (linked($map, $y, $x)) {
      $map->tile($y, $x)->{linked} = 1;
      next;
    }

    if (percent 50) {
      if ($map->_get($y + 1, $x - 1) eq " " and $x - 2 > 0) {
        $map->mod($y + 1, $x - 1, "v");
        $map->tile($y + 1, $x - 1)->{left} = 1;
        if ($map->get($y + 2, $x - 2) eq " ") {
          $map->mod($y + 2, $x - 2, "*");
          unshift @clouds, [$y + 2, $x - 2];
        }
      } elsif ($map->_get($y + 1, $x + 1) eq " " and $x + 2 < $map->width) {
        $map->mod($y + 1, $x + 1, "v");
        $map->tile($y + 1, $x + 1)->{right} = 1;
        if ($map->get($y + 2, $x + 2) eq " ") {
          $map->mod($y + 2, $x + 2, "*");
          unshift @clouds, [$y + 2, $x + 2];
        }
      }
    } else {
      if ($map->_get($y + 1, $x + 1) eq " " and $x + 2 < $map->width) {
        $map->mod($y + 1, $x + 1, "v");
        $map->tile($y + 1, $x + 1)->{right} = 1;
        if ($map->get($y + 2, $x + 2) eq " ") {
          $map->mod($y + 2, $x + 2, "*");
          unshift @clouds, [$y + 2, $x + 2];
        }
      } elsif ($map->_get($y + 1, $x - 1) eq " " and $x - 2 > 0) {
        $map->mod($y + 1, $x - 1, "v");
        $map->tile($y + 1, $x - 1)->{left} = 1;
        if ($map->get($y + 2, $x - 2) eq " ") {
          $map->mod($y + 2, $x - 2, "*");
          unshift @clouds, [$y + 2, $x - 2];
        }
      }
    }
    push @clouds, [$y, $x];   # Try it again
  }

  # Strip out wasted space on the sides and count the number of each thing.
  foreach my $x (1, -2) {
    while (1) {
      my $clear = 1;
      foreach my $y (1 .. $map->height - 1) {
        $clear = 0, last if $map->{Map}[$y][$x]{_} ne " ";
      }
      last unless $clear;
      splice(@$_, $x, 1) foreach @{ $map->{Map} };
    }
  }
  my $numclouds = ceil(($map->width - 1) / 2) + 1;
  my $numbelts = $map->width - 1 - $numclouds;

  #$map->_dump;
  my $real = BDSM::Map->new(9 * ($map->height - 1), $numclouds * 33 + $numbelts * 9, " ");

  # Lawl, so that was just stage 1. Now transform this all to something more fun.

  my $cloud = BDSM::DunGen::Shape->new("content/cloud.map");
  foreach my $y (1 .. $map->height - 1) {
    my $Y = ($y - 1) * 9;
    my $X = 0;
    foreach my $x (1 .. $map->width - 1) {
      $X += $x % 2 == 1 ? 9 : 18;
      my $tile = $map->tile($y, $x);
      if ($tile->{_} eq "*" and $y != $map->height - 1) {
        $cloud->place(on => $real, at => [$Y, $X], forceblit => 1);
      } elsif ($tile->{_} eq "^" and $tile->{left}) {
        BDSM::Toy::Conveyor->new($real, -at => [$Y - 2, $X + 1], -length => 12, -dir => "nw");
      } elsif ($tile->{_} eq "^" and $tile->{right}) {
        BDSM::Toy::Conveyor->new($real, -at => [$Y - 1, $X + 9], -length => 10, -dir => "ne");
      } elsif ($tile->{_} eq "v" and $tile->{left}) {
        BDSM::Toy::Conveyor->new($real, -at => [$Y - 1, $X + 9], -length => 10, -dir => "sw");
      } elsif ($tile->{_} eq "v" and $tile->{right}) {
        BDSM::Toy::Conveyor->new($real, -at => [$Y - 2, $X + 2], -length => 12, -dir => "se");
      }
    }
  }
  foreach my $y ($real->height - 9 .. $real->height) {
    foreach my $x (0 .. $real->width) {
      next unless $real->get($y, $x) eq " " or $real->get($y, $x) eq ".";
      if ($y == $real->height - 9) {
        $real->mod($y, $x, "#");
        $real->mod($y, $x, symbol => " ", "white");
        #$real->tile($y, $x)->{spawnpt} = "main";
      } else {
        my $sym = percent(80) ? " " : "%";
        $real->mod($y, $x, symbol => $sym, "black/white");
      }
    }
  }

  #for my $y (0 .. $real->height) {
    #for my $x (0 .. $real->width) {
      #$real->del($y, $x, "symbol");
    #}
  #}

  $real->{_Data}{$_} = 1 for qw(empty superlight nostairs);

  return $real;
}

sub linked {
  my ($map, $y1, $x1) = @_;
  my $seen = [];
  my @heap = ([$y1, $x1]);
  while (my $node = shift @heap) {
    my ($y, $x) = @$node;
    return 1 if $map->tile($y, $x)->{linked};
    return 1 if $y == $map->height - 1; # Acceptable, also.
    next if $seen->[$y][$x];
    $seen->[$y][$x] = 1;

    push @heap, [$y - 2, $x - 2] if $map->_get($y - 1, $x - 1) eq "^";
    push @heap, [$y - 2, $x + 2] if $map->_get($y - 1, $x + 1) eq "^";
    push @heap, [$y + 2, $x - 2] if $map->_get($y + 1, $x - 1) eq "v";
    push @heap, [$y + 2, $x + 2] if $map->_get($y + 1, $x + 1) eq "v";
  }
  return;
}

42;
