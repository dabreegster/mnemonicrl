package BDSM::Map::Transform;

use strict;
use warnings;
use Util;

use BDSM::Vector;

# We simply extend BDSM::Map with more methods. Those in BDSM::Map are accessors mostly; we
# transform maps... Wow, you'd think package names would be obvious.

# Fills the map with the specified tile from range [Y, X] to [Y, X].
sub fill {
  my ($self, $from, $to, @with) = @_;
  # What happens in the dungeon stays in the dungeon...
  # (Old joke when I used to screw up encapsulation. STILL RELEVANT SOMEHOW.)
  $self->check(@$from);
  $self->check(@$to);
  my ($y1, $x1) = @$from;
  my ($y2, $x2) = @$to;
  foreach my $y ($y1 .. $y2) {
    foreach my $x ($x1 .. $x2) {
      $self->mod($y, $x, @with);
    }
  }
}

# Properly border an entire map with some complex rules.
sub border {
  # TODO: Here be dragons... I've forgotten all of this. No really, this is
  # magick.
  my $self = shift;
  my $map = $self->{Map};
  my $cnty = 0;
	# We munge directly cause we can and cause it's faster.
  foreach my $y (0 .. $self->height) {
    my $cntx = 0;
    foreach my $x (0 .. $self->width) {
      $map->[$y][$x]{_}= "#"
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
				$x != $self->width
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
				$x != $self->width
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
				$x != $self->width
      and
        $map->[$y - 1][$x + 1]{_} eq " ";
      $map->[$y][$x]{_} = "#" if $cnty == $self->height;
      $cntx++;
    }
    $map->[$y][-1]{_} = "#" if $map->[$y][-1]{_} eq ".";
    $cnty++;
  }
}

# Run game of life rules for a number of iterations.
sub cellular {
  my ($map, $iters) = @_;
  my $old = [];
  $iters++ if $iters % 2 == 0;  # Even number of iterations "inverts" the map
  foreach (1 .. $iters) {
    # Store old copy!
    foreach my $y (0 .. $map->height) {
      foreach my $x (0 .. $map->width) {
        $old->[$y][$x] = $map->{Map}[$y][$x]{_};
      }
    }

    # Apply Game of Life rules
    foreach my $y (1 .. $map->height - 1) {
      foreach my $x (1 .. $map->width - 1) {
        # How many neighbors?
        my $neighbors = 0;
        $neighbors++ if $old->[$y - 1][$x - 1] eq "#";
        $neighbors++ if $old->[$y - 1][$x]     eq "#";
        $neighbors++ if $old->[$y - 1][$x + 1] eq "#";
        $neighbors++ if $old->[$y][$x - 1]     eq "#";
        $neighbors++ if $old->[$y][$x + 1]     eq "#";
        $neighbors++ if $old->[$y + 1][$x - 1] eq "#";
        $neighbors++ if $old->[$y + 1][$x]     eq "#";
        $neighbors++ if $old->[$y + 1][$x + 1] eq "#";
        $map->{Map}[$y][$x]{_} = $neighbors < 3 ? "#" : ".";
      }
    }
  }
}

# Simply change any walls to floors unless a blank space is adjacent to them.
sub excavate {
  my $map = shift;
  foreach my $y (1 .. $map->height - 1) {
    WALL: foreach my $x (1 .. $map->width - 1) {
      next unless $map->{Map}[$y][$x]{_} eq "#";
      foreach (adjacent_tiles("diag", $y, $x)) {
        my ($Y, $X) = @$_;
        next WALL if $map->{Map}[$Y][$X]{_} eq " ";
      }
      $map->{Map}[$y][$x]{_} = ".";
    }
  }
}

# A generic pattern of expansion. Each iteration can be scheduled or ASAP recursive
sub flood {
  my ($map, $opts) = args @_;

  my %flooded;
  my @pts = (@{ $opts->{from} });
  if ($opts->{each_node}) {
    $opts->{each_node}->($map, @$_) foreach @pts;
  }
  my $iter = 1;

  $opts->{tags} //= [];
  my $do;
  $do = sub {
    my @next;
    foreach my $src (@pts) {
      foreach (adjacent_tiles($opts->{dir}, @$src)) {
        my ($y, $x) = @$_;
        next unless $map->stfucheck($y, $x);
        next if $flooded{"$y,$x"};
        if ($opts->{valid}) {
          next unless $opts->{valid}->($map->tile($y, $x));
        } else {
          next unless $map->permeable($y, $x);
        }
        $flooded{"$y,$x"} = 1;
        push @next, [$y, $x];
        $opts->{each_node}->($map, $y, $x) if $opts->{each_node};
      }
    }
    $opts->{each_iter}->($map, @next) if $opts->{each_iter};
    return "STOP" if $opts->{iters} and ++$iter > $opts->{iters};
    if (@next) {
      @pts = @next;
      if ($opts->{asap}) {
        return $do->();
      } else {
        return $opts->{delay} // 0;
      }
    } else {
      return "STOP";
    }
  };

  if ($opts->{asap}) {
    $do->();
  } else {
    GAME->schedule(
      -tags => ["map", "flood", @{ $opts->{tags} }],
      -id   => "flood$map->{Depth}",
      -do   => $do
    );
  }
}

# From the perspective of the upper stair
sub stair {
  my ($upper, $args, $y1, $x1, $z, @to) = args @_;
  push @{ $upper->{_Data}{Stairs} }, [$y1, $x1, $z, @to];

  $upper->tile($y1, $x1)->{Stair} = [$z, @to];
  $upper->mod($y1, $x1, ">") unless $upper->get($y1, $x1) eq "<";

  if (GAME->{LogicMap}) {
    my $depth = $upper->{Depth} // $upper->{_Data}{Depth};
    GAME->{LogicMap}{$depth}{$z} ||= [];
    push @{ GAME->{LogicMap}{$depth}{$z} }, [$y1, $x1];
    $upper->influence_map($z, $y1, $x1) unless GAME->{NoDiffuse};
  }

  if (GAME->fullsim and !$args->{oneway} and @to == 2) {
    my $lower;
    my $our_z = $upper->{Depth} // $upper->{_Data}{Depth} // die "cant link stairs to $z if we dunno our depth\n";
    my $dat = [@to, $our_z, $y1, $x1];
    if ($lower = GAME->{Levels}{$z}) {
      $lower->tile(@to)->{Stair} = [$our_z, $y1, $x1];
      $lower->mod(@to, "<");
      # TODO but they need to know its < too
      push @{ $lower->{_Data}{Stairs} }, $dat;
    } else {
      push @{ GAME->{PendingStairs}{$z} }, $dat;
    }
  }
}

# Discover doors on a floor, transform them visually, and mark info
sub hotel_doors {
  my $map = shift;
  my $doors = {};
  my $dat = $map->{_Data};
  my @nums = $dat->{RoomOrder} ? @{ $dat->{RoomOrder} } : shuffle(300 .. 399);
  $dat->{RoomOrder} = [@nums];

  foreach my $y (0 .. $map->height) {
    foreach my $x (0 .. $map->width) {
      my $tile = $map->tile($y, $x);
      next unless $tile->{_} eq "+";
      my $color = $map->toplayer($y, $x, "symbol");
      $color = $color ? $color->[2] : "grey";

      my $rm = shift @nums;
      my @sign = ("[", split(//, $rm), "]");
      $doors->{$rm} = [$y, $x];
      $tile->{HotelRm} = $rm;

      # How're we oriented?
      if ($map->get( dir_relative("north", $y, $x) ) eq " ") {
        $map->mod($y, $x - 1, symbol => "|", $color);
        $map->mod($y, $x + 1, symbol => "|", $color);
        my $X = $x - 2;
        $map->mod($y - 2, $X++, name => $_, $color) for @sign;
      } elsif ($map->get( dir_relative("south", $y, $x) ) eq " ") {
        $map->mod($y, $x - 1, symbol => "|", $color);
        $map->mod($y, $x + 1, symbol => "|", $color);
        my $X = $x - 2;
        $map->mod($y + 2, $X++, name => $_, $color) for @sign;
      } elsif ($map->get( dir_relative("west", $y, $x) ) eq " ") {
        $map->mod($y - 1, $x, symbol => "-", $color);
        $map->mod($y + 1, $x, symbol => "-", $color);
        my $X = $x - 2;
        $map->mod($y, $X--, name => $_, $color) for reverse @sign;
      } elsif ($map->get( dir_relative("east", $y, $x) ) eq " ") {
        $map->mod($y - 1, $x, symbol => "-", $color);
        $map->mod($y + 1, $x, symbol => "-", $color);
        my $X = $x + 2;
        $map->mod($y, $X++, name => $_, $color) for @sign;
      }
    }
  }

  return $doors;
}

42;
