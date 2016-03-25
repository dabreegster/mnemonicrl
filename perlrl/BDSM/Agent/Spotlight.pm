package BDSM::Agent::Spotlight;

use strict;
use warnings;
use Util;

use base "Game::Object";
__PACKAGE__->announce("Spotlight");

# Bounces around a map lighting it up in fun ways
sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(Filler => 1);
  $self->_construct(\%opts => "Map", "Color");
  $self->{Tick} = 0;

  if ($opts{Size} eq "small") {
    $self->{Mask} = [
      [split(//, "  ....  ")],
      [split(//, "........")],
      [split(//, "........")],
      [split(//, "  ....  ")],
    ];
  } elsif ($opts{Size} eq "medium") {
    $self->{Mask} = [
      [split(//, "  ........  ")],
      [split(//, "............")],
      [split(//, "............")],
      [split(//, "............")],
      [split(//, "............")],
      [split(//, "  ........  ")],
    ];
  } elsif ($opts{Size} eq "large") {
    $self->{Mask} = [
      [split(//, "  ............  ")],
      [split(//, "................")],
      [split(//, "................")],
      [split(//, "................")],
      [split(//, "................")],
      [split(//, "................")],
      [split(//, "................")],
      [split(//, "  ............  ")],
    ];
  }

  my $map = $self->{Map};
  $map->{_Data}{superlight} = 0;
  $map->{_Data}{initlight} = 1;

  if ($opts{At}) {
    $self->go(@{ $opts{At} });
  } else {
    $self->go(
      random(0, $map->height - $self->height),
      random(0, $map->width - $self->width)
    );
  }
  $self->{VelX} = choosernd(-1, 1);
  $self->{VelY} = choosernd(-1, 1);

  $self->schedule(
    -do => "move", -tags => ["spotlight"], -id => "spotlight_$self->{ID}"
  ) unless delete $opts{no_bounce};

  return $self;
}

# These return indices, thats height - 1 for instance
sub width {
  my $self = shift;
  #return scalar @{ $self->{Mask}[0] };
  return $#{ $self->{Mask}[0] };
}

sub height {
  my $self = shift;
  #return scalar @{ $self->{Mask} };
  return $#{ $self->{Mask} };
}

sub void {
  my $self = shift;
  return !defined $self->{Y};
}

# TODO All util methods, yeah, i've gotten lazy ^^;
sub go {
  my ($self, $y, $x) = @_;

  $self->_blit(0) unless $self->void;
  $self->{Y} = $y;
  $self->{X} = $x;
  $self->_blit(1);

  # TODO perhaps it should be a map job?
  UI->{Main}->drawme if UI and UI->{Main} and UI->{Main}{Map} eq $self->{Map};
}

sub _blit {
  my $self = shift;
  my $on = shift;
  foreach my $y (0 .. $self->height) {
    foreach my $x (0 .. $self->width) {
      next unless $self->{Mask}[$y][$x] eq ".";
      my $Y = $y + $self->{Y};
      my $X = $x + $self->{X};
      my $tile = $self->{Map}->tile($Y, $X);
      if ($on) {
        #$tile->{ColorLight} = $self->{Color};
        $tile->{Lit} = 2;
      } else {
        $tile->{Lit} = 1;
        #delete $tile->{ColorLight};
      }
      $self->{Map}->modded($Y, $X);
    }
  }
}

sub move {
  my $self = shift;
  my $y1 = $self->{Y} + $self->{VelY};
  my $x1 = $self->{X} + $self->{VelX};

  my ($y2, $x2) = ($y1, $x1);
  $x2 = clamp($x2, 0, $self->{Map}->width - $self->width);
  $y2 = clamp($y2, 0, $self->{Map}->height - $self->height);
  $self->{VelX} *= -1 if $x1 != $x2;
  $self->{VelY} *= -1 if $y1 != $y2;

  $self->go($y2, $x2);
  return 0.05;
}

# A static fxn
sub circle {
  my ($class, %args) = @_;
  die "spotlight->circle is a static!\n" if ref $class;

  my $num    = $args{num}   || 3;
  my $speed  = $args{speed} || 0.05;
  my $rps    = $args{rps}   || 0.9;  # rotations per second
  my $center = $args{at}    || [20, 30];
  my $r      = $args{r}     || 15;  # Radius
  my $twopi  = 3.14159 * 2;  # Nah, cant configure this

  my @lights;
  push @lights, GAME->make("Spotlight",
    Map   => GAME->{Map},
    At    => $center,
    Color => ["Cyan", "Green", "yellow"]->[$_ - 1],
    Size  => "medium",
    no_bounce => 1
  ) for 1 .. $num;
  my $t = 0;

  GAME->schedule(
    -id => "spotlight_circle",
    -tags => ["spotlight"],
    -do => sub {
      $t += $twopi * $speed * $rps;
      for my $i (0 .. $#lights) {
        my $theta = $t + $i * ($twopi / $num);
        $lights[$i]->go(
          $center->[0] + ($r / 2) * sin($theta),
          $center->[1] + $r * cos($theta),
        );
      }
      return $speed;                                                   
    }
  );
  GAME->schedule(
    -id => "spotlight_converger",
    -tags => ["spotlight"],
    -do => sub {
      $r-- if $r > 5;
      return 0.6;
    }
  );
}

42;
