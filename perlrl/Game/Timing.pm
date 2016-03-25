package Game::Timing;

use strict;
use warnings;
use Util;

# Set up the DB.
GAME->{Timers} = bless {}, __PACKAGE__; # A great heap of timers we are

# Start a POE session for game events.
use Time::HiRes ("time");
use POE;
POE::Session->create(
  inline_states => {
    _start => sub {
      $_[KERNEL]->alias_set("gameworld");
    },
    tick   => \&_tick,
    untick => \&_untick
  }
);

# Handle timed game events.
sub schedule {
  my ($self, $opts) = args @_;
  my $event = {
    Callback  => $opts->{do},
    Args      => $opts->{args} || [],
    ID        => $opts->{id},
    InitDelay => $opts->{delay}
  };
  $event->{$_} = 1 foreach @{ $opts->{tags} };
  debug "event $opts->{id} already!" if $self->{ $opts->{id} };
  $self->{ $opts->{id} } = $event;
  POE::Kernel->post(gameworld => "tick", $opts->{id});
}

sub _tick {
  my $db = GAME->{Timers};
  my $id = $_[ARG0];

  my $timer = $db->{$id};
  if ($timer->{Borndead}) {
    # We're finished before we started. Reap.
    delete $db->{$id};
    return;
  }

  my $delay;
  my $start = time; # TODO
  if ($timer->{InitDelay}) {
    # Don't even do the callback yet
    $delay = delete $timer->{InitDelay};
  } elsif (ref $timer->{Callback} eq "ARRAY") {
    my ($agent, $method) = @{ $timer->{Callback} };
    $delay = $agent->$method(@{ $timer->{Args} });
  } else {
    if (ref $timer->{Callback} ne "CODE") {
      # TODO triggered by killing something in single by firing
      # or by being interrupted in explore..
      debug ["blank timer", $timer];
      return;
    }
    $delay = $timer->{Callback}->(@{ $timer->{Args} });
  }
  if ($delay eq "STOP") {
    delete $db->{$id};
    return;
  }
  #debug "$id: " . (time - $start);
  die "tick $id wants to wait $delay!!!" if $delay < 0;
  $timer->{Alarm} = POE::Kernel->delay_set("tick" => $delay, $id);
}

sub unschedule {
  my ($self, $match) = args @_;
  $match->{tags} //= [];
  TIMER: while (my ($id, $timer) = each %$self) {
    next if $match->{id} and $timer->{ID} ne $match->{id};
    if ($match->{actor}) {
      next if ref $timer->{Callback} ne "ARRAY";
      # We don't always have an object associated with the timer
      # And either our timer or our match does not always have an ID. So we use perl's
      # stringify-an-object uniqueness to our advantage
      next if ref $timer->{Callback} ne "ARRAY" or $timer->{Callback}[0] ne $match->{actor};
    }
    foreach my $tag (@{ $match->{tags} }) {
      next TIMER unless $timer->{$tag};
    }
    POE::Kernel->call(gameworld => "untick", $self, $id);
  }
}

sub _untick {
  my $db = $_[ARG0];
  my $id = $_[ARG1];
  my $timer = $db->{$id};
  if ($timer->{Alarm}) {
    POE::Kernel->alarm_remove($timer->{Alarm});
    delete $db->{$id};
  } else {
    # We're unscheduling a timer before it even fired the first time and got an alarm. Just
    # mark this.
    $timer->{Borndead} = 1;
  }
}

42;
