package BDSM::Toy::Swingy;

# TODO all of this

# some IDs would be great

use strict;
use warnings;
use Util;

use base "BDSM::Toy";

sub new {
  # TODO i dont feel like fixing args yet
  my $class = shift;
  my ($map, $args) = args @_;
  my $swing = $class->SUPER::new($map, %$args);

  my $y_range = 3;
  my $x_range = 20;
  my $halfx = $x_range / 2;
  my ($y0, $x0) = (8, 18);

  my $swing = GAME->make(Sprite =>
    FloatingBlit => 1,
    Filler       => 1,
    Map          => $map,
    At           => [$y0, $x0],
    Shapes       => {
      default => BDSM::Map->new("content/hotel/furniture/chandelier.map")
    }
  );

  return $swing;
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
}


my $x1 = $x0 - $halfx;
my $x2 = $x0 + $halfx;
my $dx = 1;
my $coeff = $y_range / ($halfx ** 2);

my @chain;
$swing->schedule(
  -tags => ["ui", "swing"], -id => "lobby_swing", -do => sub {

    # Delete the old chain
    foreach (@chain) {
      delete $map->tile(@$_)->{Layers};
      $map->modded(@$_);
    }

    # Parablic motion, wow
    my $x = $swing->{X} + $dx;
    my $y = $y0 - int($coeff * (($x - $x0) ** 2));
    $swing->go(-stages => ["Before", "On"], $y, $x);
    $dx = -1 if $swing->{X} == $x2;
    $dx = +1 if $swing->{X} == $x1;

    # Then handle the chain
    @chain = $map->line(
      0, $x0 + $halfx, $y + $swing->height - 1, $x + int($swing->width / 2) + 1
    );
    my $sym;
    if ($x == $x0) {
      $sym = "|";
    } elsif ($x > $x0) {
      $sym = "\\";
    } else {
      $sym = "/";
    }
    $map->mod(@$_, symbol => $sym, "orange") foreach @chain;

    UI->{Main}->drawme;
    return 0.3;
  },
);

42;
