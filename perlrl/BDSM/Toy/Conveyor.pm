package BDSM::Toy::Conveyor;

# some IDs would be great

use strict;
use warnings;
use Util;

use base "BDSM::Toy";

# TODO: if we die on a belt, in cleanup, gotta tell us that it's dead
# TODO: items

sub new {
  # TODO i dont feel like fixing args yet
  my $class = shift;
  my ($map, $args) = args @_;
  my $belt = $class->SUPER::new($map, %$args);
  $map->{_Data}{Effects}{conveyor} = 1;

  $belt->setup($map, %$args);
  return $belt;
}

sub setup {
  my ($belt, $map, %args) = @_;

  $map->{Toys}{Conveyors}{$belt} = $belt;
  @{ $belt->{Data} } = ("Conveyor", %args);

  my ($y1, $x1) = @{ $args{at} };
  my $dir = $args{dir};
  my $len = $args{length};

  $belt->{Dir} = $dir;
  $belt->{Agents} = {};
  $belt->{Len} = $len;

  my $activate = sub {
    my (undef, $agent, $from) = @_;
    # Uses closure magic to know this $belt
    return 1 if $belt->{Agents}{ $agent->{ID} };  # Already on
    $belt->{Agents}{ $agent->{ID} } = $agent;
    if (keys %{ $belt->{Agents} } == 1) {
      GAME->schedule(
        -do   => [$belt, "loop"],
        -id   => ["belt_$belt"],  # TODO id system for non-objects
        -tags => ["belt", "map"],
        -args => [CFG->{Misc}{BeltSpeed}]
      );
    }
  };

  # Draw it and be able to activate it
  if ($dir eq "e" or $dir eq "w") {
    $belt->{Sym} = "|";
    $belt->{Y1} = $belt->{Y2} = $y1 + 1;
    $belt->{X1} = $x1;
    $belt->{X2} = $x1 + $len;
  } elsif ($dir eq "n" or $dir eq "s") {
    $belt->{Sym} = "_";
    $belt->{Y1} = $y1;
    $belt->{Y2} = $y1 + $len;
    $belt->{X1} = $belt->{X2} = $x1 + 1;
  } elsif ($dir eq "ne" or $dir eq "sw") {
    $belt->{Sym} = "\\";
    $belt->{Y1} = $y1;
    $belt->{X1} = $x1;
  } elsif ($dir eq "nw" or $dir eq "se") {
    $belt->{Sym} = "/";
    $belt->{Y1} = $y1;
    $belt->{X1} = $x1;
  }

  # Do a check here too, actually. If we catch a collision in draw(), we can safely delete
  # ->{Toy} off of every tile, see.
  foreach ($belt->tiles) {
    return if $map->tile(@$_)->{Toy};
  }
  $map->tile(@$_)->{Toy} = $belt foreach $belt->tiles;
  if (GAME->fullsim) {
    $map->tile(@$_)->{OnEnter} = $activate foreach $belt->tiles;
  }
  return $belt->draw($map);
}

# We want it
sub orig_at {
  my $belt = shift;
  my %origdat = (@{ $belt->{Data} })[1 .. $#{ $belt->{Data} }];
  return (@{ $origdat{at} });
}

sub draw {
  my ($belt, $map) = @_;
  my ($y1, $x1) = $belt->orig_at;
  my $dir = $belt->{Dir};
  my $len = $belt->{Len};

  # TODO factor out this pattern plox
  my (@sides, @sidesym, @arrows, @arrowsym);

  # Draw it and be able to activate it
  if ($dir eq "e" or $dir eq "w") {
    @sidesym = ("-", "grey");
    foreach my $y ($y1, $y1 + 2) {
      foreach my $x ($x1 .. $x1 + $len) {
        push @sides, [$y, $x];
      }
    }

    @arrowsym = ($dir eq "e" ? ">" : "<", "Black");
    @arrows = ([$y1, $x1], [$y1 + 2, $x1], [$y1, $x1 + $len], [$y1 + 2, $x1 + $len]);
  } elsif ($dir eq "n" or $dir eq "s") {
    @sidesym = ("|", "grey");
    foreach my $y ($y1 .. $y1 + $len) {
      foreach my $x ($x1, $x1 + 2) {
        push @sides, [$y, $x];
      }
    }

    @arrowsym = ($dir eq "n" ? "^" : "v", "Black");
    @arrows = ([$y1, $x1], [$y1, $x1 + 2], [$y1 + $len, $x1], [$y1 + $len, $x1 + 2]);
  } elsif ($dir eq "ne" or $dir eq "sw") {
    @sidesym = ("/", "grey");
    foreach (0 .. $len) {
      push @sides, [$len + $y1 - $_, $x1 + $_], [$len + $y1 - $_, $x1 + $_ + 2];
    }

    @arrowsym = ($dir eq "ne" ? ">" : "<", "Black");
    @arrows = ([$y1, $x1 + $len], [$y1, $x1 + $len + 2], [$y1 + $len, $x1], [$y1 + $len, $x1 + 2]);
  } elsif ($dir eq "nw" or $dir eq "se") {
    @sidesym = ("\\", "grey");
    foreach (0 .. $len) {
      push @sides, [$y1 + $_, $x1 + $_], [$y1 + $_, $x1 + $_ + 2];
    }

    @arrowsym = ($dir eq "nw" ? "<" : ">", "Black");
    @arrows = ([$y1, $x1], [$y1, $x1 + 2], [$y1 + $len, $x1 + $len], [$y1 + $len, $x1 + $len + 2]);
  }

  # Actually, let's check to make sure we're not about to collide with another toy..
  foreach (@sides, @arrows) {
    if ($map->tile(@$_)->{Toy}) {
      delete $map->tile(@$_)->{Toy} foreach $belt->tiles;
      return;
    }
  }
  $map->tile(@$_)->{Toy} = $belt foreach @sides, @arrows;
  $map->mod(@$_, "#") foreach @sides, @arrows;
  $map->mod(@$_, symbol => @sidesym) foreach @sides;
  $map->mod(@$_, symbol => @arrowsym) foreach @arrows;
  $map->mod(@$_, "_") foreach $belt->tiles;

  #$map->tile(@$_)->{Lit} = 1 foreach $belt->tiles, @sides, @arrows;
  return $belt;
}

# Move things on us
sub loop {
  my ($belt, $delay) = @_;

  my $dir = $belt->{Dir};
  foreach (values %{ $belt->{Agents} }) {
    if ($_->$dir == 0 or $_->tile->{_} ne "_") {
      delete $belt->{Agents}{ $_->{ID} };
    }
  }
  return "STOP" unless keys %{ $belt->{Agents} };

  return $delay;
}

sub tiles {
  my $belt = shift;
  my @ls;
  if ($belt->{Y2}) {
    # Orthogonal, easy
    foreach my $y ($belt->{Y1} .. $belt->{Y2}) {
      foreach my $x ($belt->{X1} .. $belt->{X2}) {
        push @ls, [$y, $x];
      }
    }
  } elsif ($belt->{Sym} eq "\\") {
    # So it goes like this: /
    push @ls, [$belt->{Len} + $belt->{Y1} - $_, $belt->{X1} + $_ + 1] foreach 0 .. $belt->{Len};
  } elsif ($belt->{Sym} eq "/") {
    # So it goes like this: \
    push @ls, [$belt->{Y1} + $_, $belt->{X1} + $_ + 1] foreach 0 .. $belt->{Len};
  }
  return @ls;
}

42;
