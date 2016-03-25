package BDSM::Agent::Sprite;

use strict;
use warnings;
use Util;

use base "BDSM::Agent";
__PACKAGE__->announce("Sprite");

# We're multi-tiled
sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts, no_init => 1);
  return if $opts{no_init};
  $self->_construct(\%opts => "Map", "Color", "FloatingBlit", "Render");

  $self->{Aggregate} = $self;

  # Carve our shapes!
  $self->{Shapes}{$_} = $self->_carve($opts{Shapes}->{$_}) foreach keys %{ $opts{Shapes} };
  $self->{CurShape} = $opts{Shape} // "default";
  $self->{Shape} = $self->{Shapes}{ $self->{CurShape} };
  die "what does this sprite look like, hmm?" unless $self->{Shape};

  # Going somewhere already?
  if ($self->{Map}) {
    my $get = $opts{At} ? $self->go(-nointeract => 1, @{ $opts{At} }) : $self->warp;
    # Don't join the map? Sprites arent people too?
  }

  return $self;
}

sub _carve {
  # Turn a multi-lined string into a 2D shape.
  my ($self, $string) = @_;

  if (ref $string) {
    my $shape = [];
    foreach my $y (0 .. $string->height) {
      foreach my $x (0 .. $string->width) {
        $shape->[$y][$x] = " ";
        my $sym = $string->toplayer($y, $x, "symbol");
        if (!$sym and my $char = $string->get($y, $x)) {
          $sym = ["blah", $char, "grey"] unless $char eq " ";
        }
        if ($sym) {
          $shape->[$y][$x] = {
            Sprite    => $self,
            Aggregate => $self,
            Symbol    => $sym->[1],
            Color     => $sym->[2]
          };
        }
      }
    }
    return $shape;
  }

  my @rows = split(/\n/, $string);

  my $width = 0;  # Longest of rows, pad the rest
  foreach (@rows) {
    my $len = length($_);
    $width = $len if $len > $width;
  }
  # Pad if we have to
  @rows = map { $_ . " " x ($width - length($_)) } @rows;

  # Form the shape.
  my $shape = [];
  foreach my $row (@rows) {
    # We don't make piece symbols if we're just a blank space
    push @$shape, [ map {
      my $a = $_; $a = $self->{Render}{$a} if $self->{Render}{$a};
      $_ eq " " ? " " : {
        Aggregate => $self,   # When you bully a piece, you bully a village...
        Sprite    => $self,   # But we still have a sense of $self. In a blob, together.
        Symbol    => $a,
        Color     => $self->{Color}
    } } split(//, $row) ];
  }

  return $shape;
}

sub _dump {
  # Quick and simple dump to STDERR in a format suitable for viewing with most(1)
  my $self = shift;
  foreach my $row (@{ $self->{Shape} }) {
    print STDERR join("", map { ref $_ ? $_->{Symbol} : $_ } @$row) . "\n";
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

sub _preblit {
  my ($self, $heap, $Y, $X, $interact) = @_;
  return 1 if $self->{FloatingBlit};  # Blit with impunity!

  foreach my $y (0 .. $self->height) {
    foreach my $x (0 .. $self->width) {
      next unless ref $self->{Shape}[$y][$x];

      return unless $self->{Map}->stfucheck($y + $Y, $x + $X);  # Valid coordinates?

      my $tile = $self->{Map}->get($y + $Y, $x + $X);

      # Something's there, but it may not even warrant a collision...
      if (ref $tile) {
        # When go() and transform() call us, the current shape may still exist on the map.
        # Since it'll disappear if there are no other conflicts, we can ignore colliding
        # with ourselves.
        next if $tile->{Aggregate} == $self;  # Entire blob
        next if $tile->{Sprite} == $self;     # One sprite in the blob

        return unless $interact;
        # If we're not in a Blob and collide with a Blob, push entire Blob
        # If we push something in a Blob and we're in it too, just push the thing
        # If our Aggregate isn't us, we're in a Blob.
        if ($self->{Aggregate} == $self) {
          return $self->fxn("WhenCollide", $heap, $tile->{Aggregate}, $Y, $X);
        } else {
          return $self->fxn("WhenCollide", $heap, $tile->{Sprite}, $Y, $X);
        }
      } else {
        return unless $self->{Map}->permeable($tile);
      }
    }
  }
  return 1;
}

sub _blitoff {
  my $self = shift;
  return if $self->void;
  foreach my $y (0 .. $self->height) {
    foreach my $x (0 .. $self->width) {
      next unless ref $self->{Shape}[$y][$x];
      delete $self->{Map}->tile($self->{Y} + $y, $self->{X} + $x)->{Actor};
      $self->{Map}->modded($self->{Y} + $y, $self->{X} + $x);
    }
  }
}

sub _bliton {
  my $self = shift;
  foreach my $y (0 .. $self->height) {
    foreach my $x (0 .. $self->width) {
      next unless ref $self->{Shape}[$y][$x];
      $self->{Map}->tile($self->{Y} + $y, $self->{X} + $x)->{Actor} = $self->{Shape}[$y][$x];
      $self->{Map}->modded($self->{Y} + $y, $self->{X} + $x);
    }
  }
}

# Crunchy
sub serialize {
  my $self = shift;

  # Do a shallow copy of the sprite's data.
  my $send = { %$self };
  delete $send->{Map};
  delete $send->{Shape};
  delete $send->{Shapes};   # Don't mod the orig reference!

  # Store its shapes. {Sprite} and {Aggregate} will both be the object. {Color} will be the
  # whole thing's Color.
  foreach my $shape (keys %{ $self->{Shapes} }) {
    $send->{Shapes}{$shape} = [];
    foreach my $row (@{ $self->{Shapes}{$shape} }) {
      push @{ $send->{Shapes}{$shape} }, join("", map { ref $_ ? $_->{Symbol} : $_ } @$row);
    }
  }
  delete $send->{Aggregate};

  return bless($send, ref $self);
}

sub unserialize {
  my ($self, $map) = @_;
  $self->{Map} = $map;
  $self->{Aggregate} = $self;

  # Recreate our shapes.
  my $shapes = {};
  foreach my $shape (keys %{ $self->{Shapes} }) {
    $shapes->{$shape} = [];
    foreach my $row(@{ $self->{Shapes}->{$shape} }) {
      push @{ $shapes->{$shape} }, [ map { $_ eq " " ? " " : {
        Aggregate => $self,   # When you bully a piece, you bully a village...
        Sprite    => $self,   # But we still have a sense of $self. In a blob, together.
        Symbol    => $_,
        Color     => $self->{Color}
      } } split(//, $row) ];
    }
  }
  $self->{Shapes} = $shapes;
  $self->{Shape} = $self->{Shapes}{ $self->{CurShape} };
}

###########################################################################################

sub BEFORE_go {
  my ($self, $heap, $y, $x) = actargs @_;
  $y = int $y; $x = int $x;
  @{ $heap->{Args} } = ($y, $x);

  # TODO: what, check EVERY OnExit?
  
  # 1) Check out where we're trying to go...
  return STOP unless $self->_preblit($heap, $y, $x, !$heap->{nointeract});
}

sub ON_go {
  my ($self, $heap, $y, $x) = actargs @_;

  # Blit off old position.
  $self->_blitoff;
  
  $self->{Y} = $y;
  $self->{X} = $x;
  
  # Blit onto new position.
  $self->_bliton;
}

###########################################################################################

sub BEFORE_warp {
  my ($self, $heap) = actargs @_;
  my ($y, $x);
  while (1) {
    ($y, $x) = $self->{Map}->spawnpt;
    # Inclusive due to border
    next if $y + $self->height >= $self->{Map}->height;
    next if $x + $self->width >= $self->{Map}->width;
    last if $self->_preblit($heap, $y, $x, 0);
  }
  return REDIRECT("go", -nointeract => 1, $y, $x);
}

###########################################################################################

sub BEFORE_transform {
  my ($self, $heap, $shape) = actargs @_;
  return STOP if $shape eq $self->{CurShape};

  # Is there room for the new shape?
  my $oldshape = $self->{Shape};
  $self->{Shape} = $self->{Shapes}{$shape};
  my $code = $self->_preblit($heap, $self->{Y}, $self->{X}, 0);
  $self->{Shape} = $oldshape;
  return STOP unless $code;
}

sub ON_transform {
  my ($self, $heap, $shape) = actargs @_;

  # 1) Disappear...
  $self->_blitoff;
  
  # 2) ... And reappear, metamorphised!
  $self->{Shape} = $self->{Shapes}{$shape};
  $self->{CurShape} = $shape;
  $self->_bliton;

  # TODO debatable
  $self->{Map}->hookshot("draw" => $self);
}

42;
