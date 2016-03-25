package BDSM::Agent::Blob;

use strict;
use warnings;
use Util;

use BDSM::Map;

use base "BDSM::Agent::Sprite";
__PACKAGE__->announce("Blob");

# WE EAT SHIT HUAAARGH
sub new {
  my ($class, %opts) = @_;
  my $self = $class->SUPER::new(%opts, no_init => 1);

  $self->_construct(\%opts => "Map", "FloatingBlit");
  $self->{Agents} = [];
  $self->{Aggregate} = $self;

  # Set up our internal BDSM::Map and the Shape reference so all of Sprite's rendering
  # routines like us.
  $self->{Grid} = BDSM::Map->new(0, 0, " ");
  $self->{Grid}{Depth} = "Blob_$self->{ID}";
  $self->_rememberus;
  $self->_recomblobulate;

  # Going somewhere already?
  if ($self->{Map}) {
    $opts{At} ? $self->go(-nointeract => 1, @{ $opts{At} }) : $self->warp;
  }

  return $self;
}

sub height {
  my $self = shift;
  return $self->{Grid}->height;
}

sub width {
  my $self = shift;
  return $self->{Grid}->width;
}

sub _recomblobulate {
  # Internally, our Grid (a BDSM::Map... literally)'s individual nodes are structured
  # differently than from a normal Sprite's Shape structure... so fix that.
  # We're VERY slow right now! Call us whenever anything on the blob changes.
  my $self = shift;
  $self->{Shape} = [];  # Always start fresh in case we've grown or shrunk
  foreach my $y (0 .. $self->height) {
    foreach my $x (0 .. $self->width) {
      $self->{Shape}[$y][$x] = $self->{Grid}->get($y, $x);
    }
  }
}

sub _prune {
  # Prune off extra junk off a BDSM::Map blob
  my (undef, $map) = (@_);

  # Prune the bottom
  BOTTOM: foreach my $y (reverse(0 .. $map->height)) {
    foreach my $x (0 .. $map->width) {
      last BOTTOM if ref $map->get($y, $x);
    }
    pop @{ $map->{Map} };
  }

  # Prune the right side
  RIGHT: foreach my $x (reverse(0 .. $map->width)) {
    foreach my $y (0 .. $map->height) {
      last RIGHT if ref $map->get($y, $x);
    }
    pop @{ $map->{Map}[$_] } foreach 0 .. $map->height;
  }

  # TODO: the top and left do end up with extra.. shit ><
  # The top and left never end up with extra because of the way the offsets work
  return $map;
}

# Cereal blobs. Gushy!
sub serialize {
  my $self = shift;

  # Do a shallow copy of the sprite's data.
  my $send = { %$self };

  # We don't even need to save our grid, just its size and all the things on it!
  delete $send->{Grid};
  $send->{GridSize} = [$self->{Grid}->height, $self->{Grid}->width];
  $send->{Agents} = [ map { $_->serialize } @{ $self->{Agents} } ];

  delete $send->{Map};
  delete $send->{Shape};
  delete $send->{Aggregate};

  return bless($send, ref $self);
}

sub unserialize {
  my ($self, $map) = @_;
  $self->{Map} = $map;
  
  $self->{Aggregate} = $self;
  $self->{Grid} = BDSM::Map->new(@{ delete $self->{GridSize} }, " ");
  $self->{Grid}{Depth} = "Blob_$self->{ID}";
  # Restore the agents
  my @agents;
  foreach (@{ $self->{Agents} }) {
    my $agent = $_->recreate($self->{Grid});
    $agent->{Aggregate} = $self;
    $agent->_bliton;
    push @agents, $agent;
  }
  $self->{Agents} = \@agents;

  $self->_recomblobulate;   # Ready to bliton, sir!
  $self->_rememberus;
}

# Oh yeah, and add a callback to the map so that when stuff happens inside it, stuff
# happens wherever the blob is too...
sub _rememberus {
  my $blob = shift;

  $blob->{Grid}->hook(Blob => $blob, sub {
    my $map = shift;
    my $blob = shift;
    my $cmd = shift;
    if ($cmd eq "mod") {
      # Mini-recomblobulate. WAY FASTER.
      my ($y, $x) = @_;   # TODO sometimes get a third, its cool
      # TODO: broken anyway, aaegh
      $blob->{Shape}[$y][$x] = $blob->{Grid}->get($y, $x);
    } elsif ($cmd eq "draw") {
      # TODO; we're uh useless 
      $blob->_blitoff;
      $blob->_bliton;
      $blob->{Map}->hookshot("draw" => $blob);
    }
  });
}

###########################################################################################

sub BEFORE_omnomnom {
  my ($blob, $heap, $agent, $offy, $offx) = actargs @_;

  # Before we mess with ANYTHING, check if the new agent can fit in the blob. Rather, the
  # blob always accomodates, but the blob's environment might not. And naturally this
  # check is only required if the blob isn't in the void.
  return if $blob->void;

  my $savemap = $agent->{Map};
  $agent->{Map} = $blob->{Map};

  my $code = $agent->_preblit($blob->{Y} + $offy, $blob->{X} + $offx);
  $agent->{Map} = $savemap;
  debug "BLOB OMNOMNOM FAILLL" unless $code;

  return STOP($agent, "not enuff room to omnomnom an agent") unless $code;
}

sub ON_omnomnom {
  my ($blob, $heap, $agent, $offy, $offx) = actargs @_;

  # When we move, let the camera follow
  $blob->{Camera} = 1 if $agent->player;

  # How big will our new blob be?
  # The calculations got a little... messy, so just make it large enough to work for sure
  # then prune the extra later.
  my $height = $blob->height + $agent->height + abs($offy);
  my $width = $blob->width + $agent->width + abs($offx);

  # Form the blank shape
  my $shape = BDSM::Map->new($height, $width, " ");
  $shape->{Depth} = "tmpshape";

  # Add an offset to old agents' position since we've potentially resized the blob.
  my $oldy = $offy > 0 ? 0 : abs($offy);
  my $oldx = $offx > 0 ? 0 : abs($offx);
  foreach my $old (@{ $blob->{Agents} }) {
    $old->{Map} = $shape;
    $old->{Y} += $oldy;
    $old->{X} += $oldx;
  }

  # And set up the new agent with its position
  # (Remove them from their previous boring BDSM::Map)
  $agent->_blitoff;
  $agent->{Aggregate} = $blob;
  $agent->{Map} = $shape;
  $agent->{Y} = $offy > 0 ? $offy : 0;
  $agent->{X} = $offx > 0 ? $offx : 0;
  push @{ $blob->{Agents} }, $agent;

  # Merge in all agents, which we conveniently have a list of.
  foreach (@{ $blob->{Agents} }) {
    $_->{Map} = $shape;
    $_->_bliton;
  }

  # If the agent is a sprite, we need to set its Aggregate to us... because we have
  # assimilated it... *burp*
  if ($agent->{Shape}) {
    foreach my $y (0 .. $shape->height) {
      foreach my $x (0 .. $shape->width) {
        next unless ref $shape->get($y, $x);
        $shape->get($y, $x)->{Aggregate} = $blob;
      }
    }
  }

  # Prune the extra map stuff off
  $blob->_prune($shape);

  # Render the new blob.
  if ($blob->void) {
    # We're still in the void? At least save our grid. :P
    $blob->{Grid}{Map} = $shape->{Map};   # Don't nuke our heap, man
    $agent->{Map} = $blob->{Grid};
    $blob->_recomblobulate;
  } else {
    $blob->_blitoff;
    $blob->{Grid}{Map} = $shape->{Map};   # Don't nuke our heap, man
    $agent->{Map} = $blob->{Grid};
    $blob->{Y} += $offy if $offy < 0;
    $blob->{X} += $offx if $offx < 0;
    $blob->_recomblobulate;
    $blob->_bliton;
  }

  # We set old agents' map to the temp shape, not our grid. Fix that
  foreach (@{ $blob->{Agents} }) {
    $_->{Map} = $blob->{Grid};
  }

  # It's been a pleasure to have you.
  $blob->{Map}->hookshot("draw" => $blob);  # Cause the blits dont call it!
}

###########################################################################################

# Remove something from the blob... -sniff-
sub ON_jailbreak {
  my ($blob, $heap, $agent, $y, $x) = actargs @_;

  # Visual
  $blob->_blitoff;
  $agent->_blitoff;
  $blob->_bliton;
  $blob->{Map}->hookshot("draw" => $blob);

  # Nuke the agent from the blob
  delete $blob->{Camera} if $agent->player;    # No longer
  my @denizens;
  foreach (@{ $blob->{Agents} }) {
    push @denizens, $_ unless $_ eq $agent;
  }
  $blob->{Agents} = \@denizens;

  # Do something with the agent
  $agent->{Aggregate} = $agent;
  if (defined($y)) {
    $agent->{Map} = $blob->{Map};
    $agent->go(-nointeract => 1, $y, $x);
  } else {
    delete $agent->{Map};
  }

  # TODO: prune blob
}

42;
