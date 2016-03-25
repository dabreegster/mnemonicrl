##########
# Object #
##########

package Roguelike::Object;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Scalar::Util ("weaken");

our $AUTOLOAD;

sub new {
  my $object = shift;
  my $self = bless {
    Base => $object,
    @_
  }, "Roguelike::Object";
  push @{ $Game->{IDs} }, $self;
  $self->{ID} = $#{ $Game->{IDs} };
  weaken($Game->{IDs}[-1]);
  my @bases = ();
  my $cur = $self;
  my $old = $Game->{Silence};
  $Game->{Silence} = 1;
  while (1) {
    last unless $cur->{Base};
    $cur = $cur->{Base};
    my $return = $cur->{Init}->($self) if $cur->{Init};
    last if defined $return and $return == -1;
  }
  $Game->{Silence} = 0 unless $old;
  return $self;
}

sub g {
  my $self = shift;
  my $data = shift;
  my $noeval = 1 if $data =~ s/^://;
  my $base = $self;
  my $var;
  while (1) { # For each parent of $self, starting with $self itself...
    $var = $base;
    my $sofar = "";
    my $start = 1;
    foreach (split(/\./, $data)) {
      if ($start) {
        $var = $var->{$_};
        $start = 0;
        $sofar = $_;
        last unless defined $var;
        next;
      }
      # If it's a blessed object, then it's a hash.
      my $ref = ref $var;
      if ($ref eq "Roguelike::Object") {
        $data =~ m/^$sofar(.*)$/;
        my $get = $1;
        $get =~ s/^\.//;
        $var = $var->g($get);
        last;
      } elsif (($ref eq "HASH" or $ref =~ m/::/) and defined $var->{$_}) {
        $var = $var->{$_};
      } elsif ($ref eq "ARRAY" and defined $var->[$_]) {
        $var = $var->[$_];
      } else {
        $var = undef;
        last;
      }
      $sofar .= ".$_";
    }
    last if defined $var;
    last unless $base->{Base};
    $base = $base->{Base};
  }
  unless (defined $var) {
    return -1 if $data =~ m/\.ID$/;
    return "";
  }
  if ($noeval) {
    return $var;
  } else {
    my @args = @_;
    @args = ($self) unless @args;
    # Whateva
    return $var->(@args) if ref $var eq "CODE";
    return $var;
  }
}

sub AUTOLOAD {
  my $self = shift;
  my $method = $AUTOLOAD;
  $method =~ s/^.*:://;
  return if $method eq "DESTROY" or $method eq 1; # Don't ask me.
  # Are we an action or just a routine?
  if ($method !~ m/^_/ and $method !~ m/_$/ and (!$self->g(":Checks.$method")))
  {
    return $self->g("Routines.$method", $self, @_);
  }
  # Are we in pass 1 (preprocessing) or pass 2 (execution)?
  if ($method =~ s/^_(.*)_$/$1/) {
    # Execution
    # Attack!
    return $self->g("Routines.$method", $self, @_) if $method eq "attack";
    unless ($self->g(":Actions.$method")) {
      debug $self->g("Name") . " doesn't have a $method action!";
      return;
    }
    return -1 if signal("Before", $self, $method, @_) == -1;
    my $return = $self->g("Actions.$method", $self, @_);
    signal("After", $self, $method, @_);
    return $return;
    #}
  } elsif ($method =~ s/^_//) {
    # Preprocessing
    my $action = $method;
    my $energy;
    my @args = @_;
    while (1) {
      if ($self->g(":Checks.$action")) {
        my @pre = $self->g("Checks.$action", $self, @args);
        if ($pre[-1] eq "-") {
          pop @pre;
          push @pre, @_;
        }
        ($energy, $action, @args) = @pre;
      } else {
        debug "There is no $action pre-check!";
      }
      if ($energy == -1) {
        return -1;
      } elsif ($energy == -42) {
        next;
      } else {
        return ($energy, $action, @args);
      }
    }
  } else {
    # Preprocessing and Execution
    $method = "_$method";
    my ($energy, $action, @args) = $self->$method(@_);
    return -1 if $energy == -1;
    $action = "_$action" . "_";
    return $self->$action(@args);
  }
}

sub tile {
  my $self = shift;
  my $y = $self->g("Y");
  my $x = $self->g("X");
  return $self->g("Area.Map.$y.$x");
}

sub subjname {
  my $self = shift;
  if ($self->g("ID") == $Player->g("ID")) {
    return "you";
  } elsif ($self->g("Unique") or shift) {
    return $self->g("Name");
  } else {
    return "the " . $self->g("Name") if $self->g("Qty") == 1;
    return $self->g("Qty") . " " . $self->g("Name") . "s";  # Shrug
  }
}

sub name {
  my $self = shift;
  return $self->g("InvName", $self);
}

sub react {
  # The syntax: to => "when [subj] verb [arg1] [arg2]", by => &$code, [when =>
  #             $priority], [the rest is put with the reaction]
  # Static reactions are marked by static = 1 in the reaction.
  my $self = shift;
  my %dat = @_;
  my @event = @{ $dat{to} };
  my $reaction = $dat{by};
  my $priority = $dat{when} || 42;
  # Now take out that data from the hash of arguments.
  delete $dat{to};
  delete $dat{by};
  delete $dat{when};
  # Parse the stimulus event thingy.
  my ($when, $subj, $verb, $arg1, $arg2) = ("", $self, "", 0, 0);
  $when = shift @event;
  # The number of things in @event helps. At this point we might have:
  # subj verb do io
  # subj verb do
  # verb do
  # verb do io
  # We just figure out if the next thing is a verb or subject. Easy!
  # Actually, the number doesn't help. Wow.
  if (ref $event[0]) {
    $subj = shift @event;
  } elsif ($Game->{Content}{ $event[0] }) {
    $subj = $Game->{Content}{ shift @event };
  }
  $verb = shift @event;
  $arg1 = shift @event || 0;
  $arg1 = $Game->{Content}{$arg1} if $Game->{Content}{$arg1};
  $arg1 = $arg1->{ID} if ref $arg1;
  $arg2 = shift @event || 0;
  $arg2 = $Game->{Content}{$arg2} if $Game->{Content}{$arg2};
  $arg2 = $arg2->{ID} if ref $arg2;
  # Create a reaction slot if there isn't one.
  if (ref $subj->{$when}{$verb}{$arg1}{$arg2} ne "ARRAY") {
    $subj->{$when}{$verb}{$arg1}{$arg2} = [ [], [], []  ];
  }
  # Figure out where the reaction should go, based on priority.
  my $ind = 1;
  $ind = 0 if $priority == 1;
  $ind = 2 if $priority == -1;
  push @{ $subj->{$when}{$verb}{$arg1}{$arg2}[$ind] }, {
    Actor => $self,
    Reaction => $reaction,
    %dat
  };
  # Mark down, with the actor, this reaction, so that it might be deactivated
  # when the actor is nuked.
  # NOTE!!!!!!!! That the order is subject, then when. Easier.
  push @{ $self->{Reactions}{ $subj->{ID} } }, "$when.$verb.$arg1.$arg2.$ind";
  return 1;
}

sub destroy {
  my $self = shift;
  # We should only be used for items!
  # Check to see if we have a quantity...
  if ($self->g("Qty") > 1) {
    $self->{Qty}--;
  } else {
    # Are we wielded?
    if ($self->g("On") eq "Weapon") {
      # Screw curses for now.
      $Game->{Silence} = 1;
      $self->g("Area.Owner")->unequip($self);
      $Game->{Silence} = 0;
    }
    $self->g("Area")->del($self->g("Index"));
    foreach (0 .. $#{ $Game->{Queue} }) {
      my $tmp = [];
      foreach (0 .. $#{ $Game->{Queue} }) {
        push @$tmp, $Game->{Queue}[$_] unless $Game->{Queue}[$_]{Actor}->g("ID") == $self->g("ID");
      }
      @{ $Game->{Queue} } = @{ $tmp };
    }
  }
}

sub msg {
  return if $Game->{Silence};
  my $self = shift;
  my $msg = shift;
  # Possessives... bit messy
  my @args = map {
    if (ref $_ eq "Roguelike::Object") {
      if ($_->g("ID") == $Player->g("ID")) {
        "your";
      } else {
        $_->subjname . "'s";
      }
    } else {
      $_;
    }
  } @_;
  $msg =~ s/\[(\d+)P\]/$args[$1 - 1]/g;
  @args = map { ref $_ eq "Roguelike::Object" ? $_->subjname : $_ } @_;
  my $subjname = $self->subjname;
  # Subject
  $msg =~ s/\[subj\]/$subjname/gi;
  # Arguments
  $msg =~ s/\[(\d+)\]/$args[$1 - 1]/g;
  # Regular verbs
  my $suffix = $self->g("ID") == $Player->g("ID") ? "" : "s";
  $msg =~ s/\[(\w+)\]/$1$suffix/g;
  # Special cases
  # Can't do conditionals in regexps... hmm. WAIT I KNOW.
  if ($self->g("ID") == $Player->g("ID")) {
    # First one
    $msg =~ s/\[([\w']+)\/([\w']+)\]/$1/g;
  } else {
    # Second one
    $msg =~ s/\[([\w']+)\/([\w']+)\]/$2/g;
  }
  # Capitalize first letter. But ignore leading <\w>s!
  if ($msg =~ m/^</) {
    $msg =~ s/^(<\w+>)(\w)/$1\U$2/;
  } else {
    $msg =~ s/^(\w)/\U$1/;
  }
  # Capitalize first letter after every punctuation mark.
  $msg =~ s/(\.|!|\?) (\w)/$1 \U$2/g;
  say $msg;
  return 1;
}

sub schedule {
  my $self = shift;
  my $priority = shift;
  my $action = shift;
  my $dep = shift;
  unshift @{ $self->{Queue} }, {
    Priority => $priority,
    Cost     => $priority,
    Energy   => 0,
    Actor    => $self,
    Action   => $action,
    Depends  => $dep,
    Type     => 1
  };
}

sub queue {
  my $self = shift;
  my $meth = shift;
  my @args = @_;
  return sub {
    my $return = $self->$meth(@args);
    # Schedule the next action. Do we have implicit ones in the queue?
    if (my $queued = $self->{Queue}[0]) {
      $meth =~ s/^_(.*)_$/$1/;
      debug "An implicit action depends on $queued->{Depends} and $meth was
      just executed. WTF?" if $queued->{Depends} and $queued->{Depends} ne 
      $meth;
      # $return should *always* be -1 in cases of errors. Or should I use 0?
      if ($queued->{Depends} and $return == -1) {
        shift @{ $self->{Queue} };
      }
    }
    unless ($self->{Queue}[0]) {
      $self->schedule(1, sub { $self->Input(); });
    }
  };
}

sub bases {
  my $self = shift;
  my @bases;
  while (1) {
    if ($self->{Base}) {
      push @bases, $self->{Base};
      $self = $self->{Base};
    } else {
      last;
    }
  }
  return @bases;
}

sub eventoff {
  my $self = shift;
  # Technically I cheat here. Below, I specifically say $self's reactions, not
  # $self's bases' reactions. But later, since $event is such a convenient
  # x.y.z type string, I... cheat.
  foreach my $subj (keys %{ $self->{Reactions} }) {
    foreach my $event (@{ $self->{Reactions}{$subj} }) {
      my $actor = $Game->{IDs}[$subj];
      foreach my $i (0 .. $#{ $actor->g("$event") }) {
        my $reaction = $actor->g("$event.$i");
        delete @{ $actor->g("$event") }[$i]
          if $reaction->{Actor}{ID} == $self->{ID} and (!$reaction->{Static});
      }
    }
  }
  return 1;
}

sub has {
  my $self = shift;
  my $item = shift;
  return 0 unless $self->{Inv}->get( $item->g("Index") );
  return $self->{Inv}->get( $item->g("Index") )->g("ID") == $item->g("ID") ? 1 : 0;
}

sub delayevent {
  my ($self, $priority, $event) = @_;
  $Game->{Queue}->add({
    Priority => $priority,
    Cost     => $priority,
    Energy   => 0,
    Actor    => $self,
    Action   => $event,
    Type     => -42,
    OrigCost => $priority
  });
}

42;
