package BDSM::Static;
# TODO deprecated, only usage is Tunnel so far.

use strict;
use warnings;
use Util;

use base "Game::Object";
__PACKAGE__->announce("Static");

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  $self->_construct(\%opts => "Map", "Render");
  my @file = slurp(delete $opts{File});
  my $grid = [];
  my $length = 0;
  
  shift @file;  # Layer 1
  while ($file[0] ne "LAYER2") {
    my @row = split(//, shift(@file));
    $length = $#row if $#row > $length;
    push @$grid, \@row;
  }
  
  # Pad the grid
  foreach my $y (0 .. $#{ $grid }) {
    push @{ $grid->[$y] }, " " foreach 0 .. $length - $#{ $grid->[$y] } - 1;
  }

  shift @file;  # Layer 2
  # Now figure out which tiles are foreground and which are background
  my $shape = [];
  my $y = 0;
  while (@file) {
    my @line = split(//, shift(@file));
    foreach my $x (0 .. $#{ $grid->[0] }) {
      my $tile = $grid->[$y][$x];
      if ($tile eq " ") {
        $shape->[$y][$x] = " ";
        next;
      }
      $tile = $self->{Render}{$tile} if $self->{Render}{$tile};
      my $layer;
      if ($x > $#line) {
        $layer = "bgstatic";
      } else {
        $layer = $line[$x] eq "1" ? "fgstatic" : "bgstatic";
      }
      $shape->[$y][$x] = [$layer, $tile, "grey"]; # TODO: color
    }
    $y++;
  }

  $self->{Shape} = $shape;
  return $self;
}

# Merge onto a map
sub blit_at {
  my ($self, $Yoff, $Xoff) = @_;
  foreach my $y (0 .. $self->height) {
    foreach my $x (0 .. $self->width) {
      my $tile = $self->{Shape}[$y][$x];
      next if $tile eq " ";
      $self->{Map}->mod($Yoff + $y, $Xoff + $x, @$tile);
    }
  }
}

sub height {
  my $self = shift;
  return $#{ $self->{Shape} };
}

sub width {
  my $self = shift;
  return $#{ $self->{Shape}[0] };
}

42;
