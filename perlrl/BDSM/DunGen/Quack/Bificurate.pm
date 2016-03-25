package BDSM::DunGen::Bificurate;

use base "BDSM::Map";

use strict;
use warnings;
use Util;

use BDSM::Vector;

use base "BDSM::Map";

sub generate {
  my ($class, $height, $width) = @_;
  my $map = $class->new($height, $width, ".");
  $map->border;
  $map->fill([1, 1], [$map->height - 1, $map->width - 1], " ");

  # Calculate the regions. Really not tough
  my %regions = (
    n => [0, 0, int($map->height / 3), $map->width],
    s => [int ((2 / 3) * $map->height), 0, $map->height, $map->width],
    w => [0, 0, $map->height, int($map->width / 3)],
    e => [0, int((2 / 3) * $map->width), $map->height, $map->width]
  );

  # I want breadth first, so no recursion. :)
  # region, pt, iteration
  my $max_iter = 3;
  my @nodes = (["s", $map->getpt(-match => " ", @{ $regions{s} }), 1]);
  while (my $node = shift @nodes) {
    my ($now, $y1, $x1, $iter) = @$node;
    for (1 .. random(2, 4)) {   # Connections per
      my $next = choosernd(grep { $_ ne $now } keys %regions);
      my ($y2, $x2) = $map->getpt(-match => " ", @{ $regions{$next} });
      #$map->draw_curve($y1, $x1, $y2, $x2);
      $map->mod(@$_, ".") foreach $map->line($y1, $x1, $y2, $x2);
      $map->mod($y1, $x1, $iter);
      push @nodes, [$next, $y2, $x2, $iter + 1] unless $iter == $max_iter;
    }
  }

  #my @steps = $map->curvify(15, 1, 15, 38);
  #$map->{Steps} = \@steps;
  #foreach my $i (1 .. $#steps) {
  #  $map->mod(@$_, "#") foreach $map->line(@{ $steps[$i - 1] }, @{ $steps[$i] });
  #}

  $map->{_Data}{$_} = 1 for qw(empty superlight nostairs);
  return $map;
}

# Wrap up the whole shebang
sub draw_curve {
  my $map = shift;
  my @steps = $map->curvify(@_);
  foreach my $i (1 .. $#steps) {
    $map->mod(@$_, ".") foreach $map->line(@{ $steps[$i - 1] }, @{ $steps[$i] });
  }
}

# Recursive curses, gotta love em.
sub curvify {
  my ($self, $y1, $x1, $y2, $x2) = @_;

  log_push("line fromm $y1, $x1 to $y2, $x2");

  if (euclid($y1, $x1, $y2, $x2) <= 10) {
    log_this("  converged!");
    log_pop;
    return [$y1, $x1];
  }

  my $cy = int(($y1 + $y2) / 2);
  my $cx = int(($x1 + $x2) / 2);
  my $theta = atan2($y2 - $y1, $x2 - $x1);
  log_this("line runs at " . angle($theta));
  $theta += choosernd(-1, 1) * (3.14159 / 4); # + or - 90
  log_this("so we go " . angle($theta));
  my $amp = random(6, 9);
  # a little sub-line perpendicular to the center...
  my @hump = ($cy + int($amp * sin($theta)), $cx + int($amp * cos($theta)));
  log_this("newpt $hump[0], $hump[1]");
  if ($self->stfucheck(@hump)) {
    my @return = ($self->curvify($y1, $x1, @hump), $self->curvify(@hump, $y2, $x2));
    log_pop;
    return @return;
  } else {
    log_this("  converged! but because of bounds.");
    log_pop;
    return [$y1, $x1];
  }
}

sub drawnext {
  return; # TODO this is tmp
  my $self = shift;
  my $steps = $self->{Steps};

  while (scalar @$steps > 1) {
    my @pts = $self->line(@{ shift @$steps }, @{ $steps->[0] });
    if (grep { $self->get(@$_) ne "." } @pts) {
      $steps->[0] = $pts[0];
    } else {
      $self->mod(@$_, "~") foreach @pts;
      last;
    }
  }
}

sub angle { shift() * 360 / 3.14159 }

42;
