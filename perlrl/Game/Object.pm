package Game::Object;

use strict;
use warnings;
use Util;

use PerlRL::Component::Game;
__PACKAGE__->announce("Object");

# Subclasses should probably call us first
sub new {
  my ($class, %opts) = @_;
  # TODO ClientID and DontShare were old params we passed in
  # prolly wanna _construct on em, except its a networkin' thang
  my $self = bless {}, $class;
  $self->_construct(\%opts => "ClientID", "DontShare", "Filler", "Global"); # TODO
  if (my $ls = $opts{EarlyConstruct}) {
    $self->_construct(\%opts => @$ls);
  }
  if (!GAME->fullsim and !$self->{Filler}) {
    debug [caller];
    debug $self;
    die "probably shouldnt happen, making obj without fullsim!\n";
  }
  if ($self->{Filler}) {
    # Don't want to collide with an object the fullsim could soon use
    $self->{ID} = GAME->{Fillers}--;
  } else {
    push @{ GAME->{Objects} }, $self;
    $self->{ID} = $#{ GAME->{Objects} };
  }

  push @{ GAME->{Global} }, $self if $self->{Global};

  return $self;
}

# Just register us with the organizer as a package
sub announce {
  PerlRL::Component::Game::register(@_);
}

# class data is 'hardcoded' as a sub
sub classdat {
  my ($package, %dat) = @_;
  die "can only call on a package! got $package\n" if ref $package;

  while (my ($key, $default) = each %dat) {
    no strict "refs";
    if (ref $default eq "HASH") {
      *{ "${package}::$key" } = sub {
        my ($self, $which) = @_;
        return $default unless ref $self; # Special
        die "get what $key from " . $self->id . "?\n" unless $which;
        return $self->{$key}{$which} // $default->{$which} // $self->super($key, $which);
      };
    } else {
      *{ "${package}::$key" } = sub {
        my $self = shift;
        my $return = $self->{$key} // $default;
        return ref $return eq "ARRAY" ? @$return : $return;
      };
    }
  }
}

# Don't blindly populate the object with every bit we pass in!
sub _construct {
  my ($self, $opts, @keys) = @_;
  foreach (@keys) {
    $self->{$_} = delete $opts->{$_} if defined $opts->{$_};
  }
}

# Here's the AUTOLOAD magic that calls methods or goes through the action sequence.
our $AUTOLOAD;

sub AUTOLOAD {
  my $self = shift;
  my $do = $AUTOLOAD;
  $do =~ s/^.*:://;
  return if $do eq "DESTROY";

  # The heap is the way different parts of an action communicate
  # We're actually a taste different, starting with options..
  my $heap = { Action => $do };
  while (@_ and $_[0] =~ m/^-\D/ and $_[0] =~ m/^-(\w+)$/) {
    shift;
    $heap->{$1} = shift;
  }
  if ($heap->{heap}) {
    # They want info back, so pull a switcheroo
    my %copy = %$heap;
    $heap = $copy{heap};
    %$heap = %copy;
  }
  $heap->{Args} = [@_]; # AAAAAARRRGS... sorry.

  my @stages = GAME->fullsim ? ("Before", "On", "After") : ("On", "After");
  @stages = @{ $heap->{stages} } if $heap->{stages};
  return $self->_do_act($heap, @stages);
}

# Invoke the actions and handle redirects and later scheduling and logging and yeah.
sub _do_act {
  my ($self, $heap, @stages) = @_;
  my $action = $heap->{Action};

  my $return = 1;   # Unless we were explicitly :STOPed, assume success
  log_this("ACT) @{[$self->id]} is doing $action: " . join ", ", @stages); # TODO do i want sprintf maybe?
  log_push;
  my $cnt = 0;  # how many action bits did we actually hit?
  foreach my $stage (@stages) {
    $stage = uc $stage;
    GAME->act_cb($stage, $self, $heap);
    my @code = $self->fxn("${stage}_$action", $heap);
    $cnt++;
    next unless @code and $code[0]; # Implicitly doing nothing at the end is fine too
    if ($code[0] eq ":STOP") {
      undef $return;
      last;
    } elsif ($code[0] eq ":NOTHING") {
      $cnt--;
    } elsif (shift @code eq ":REDIRECT") {
      my $newverb = shift @code;
      log_this("ACT) Redirecting to $newverb");
      log_pop;
      return $self->$newverb(
        -stages   => $heap->{stages},
        -redirect => 1,
        -heap     => $heap->{heap}, # We want to preserve all of this
        @code
      );
    }
    # Otherwise, fine.
  }
  log_pop;
  if ($cnt == 0 and !$heap->{redirect}) {
    debug [(caller(1))[0,1,2]];
    die $self->id . " has no $action function with specified stages!\n";
  }
  $return = $heap->{Return} if defined $heap->{Return};
  return $return;
}

# Do the general thing usually, and a specific thing occasionally.
sub fxn {
  my ($self, $fxn, @args) = @_;
  if (my $custom = $self->{Fxns}{$fxn}) {
    log_this("@{[$self->id]} is calling its custom $fxn");
    return $custom->($self, @args);
  } elsif ($self->can($fxn)) {
    log_this("@{[$self->id]} is calling $fxn");
    return $self->$fxn(@args);
  } elsif ($self->can("Fxns") and my $do = $self->Fxns($fxn)) {
    log_this("@{[$self->id]} is calling $fxn");
    return $do->($self, @args);
  }
  # If they can't do it, then silence
  return ":NOTHING";
}

# Starts searching at $self's immediate superclass or the indicated class
sub super {
  my ($self, $opts, $fxn, @args) = args @_;
  my $package = $opts->{start} ? GAME->{Templates}{ $opts->{start} } : ref $self;
  no strict "refs";
  my @isa = @{ "${package}::ISA" };
  return unless @isa;
  $package = $isa[0];
  my $call = "${package}::$fxn";
  return unless $self->can($call);
  return $self->$call(@args);
}

# Return a flattened list of every $get in $self and our ancestors
sub merge_classdat {
  my ($self, $get) = @_;
  my %ls;
  %ls = (%ls, %{ $self->{$get} }) if $self->{$get};
  no strict "refs";
  foreach my $parent ($self->_superclasses) {
    # Even if inheritance doubles up, we're a hash ^^
    my %table = %{ "${parent}::" };
    next unless $table{$get} and my $more = $parent->$get;
    %ls = (%ls, %$more);
  }
  return %ls;
}

# List of packages of our parents, internal use usually
sub _superclasses {
  my $self = shift;
  my @ls;
  my $cur = ref $self;
  no strict "refs";
  while (1) {
    push @ls, $cur;
    my @isa = @{ "${cur}::ISA" };
    last unless @isa;
    die "$cur has multiple parents\n" if @isa != 1;
    $cur = $isa[0];
  }
  return @ls;
}

# Identify this template or object uniquely.
sub id {
  my $self = shift;
  return $self->type . "_$self->{ID}";
}

# Describe an event involving objects, replacing placeholders with properly formed names.
sub saymsg {
  my $self = shift;
  my $msg = shift;
  my $channel = "game";
  if ($msg =~ s/^>//) {
    $channel = $msg;
    $msg = shift;
  }
  my @ls = ($self, @_);

  # 1) Possessives
  my @args = map { ref $_ ? $_->name("possessive") : debug($_, $msg) } @ls;
  $msg =~ s/\[(\d+)'s\]/$args[$1]/g;

  # 2) Subject
  my $subjname = $self->name("specific");
  $msg =~ s/\[subj\]/$subjname/g;
  $msg =~ s/\[the 0\]/$subjname/g;
  $subjname = $self->name("general");
  $msg =~ s/\[a 0\]/$subjname/g;

  # 3) Normal arguments
  @args = map { $_->name("specific") } @ls;
  $msg =~ s/\[the (\d+)\]/$args[$1]/g;
  @args = map { $_->name("general") } @ls;
  $msg =~ s/\[a (\d+)\]/$args[$1]/g;

  # 4) Regular verbs
  $msg =~ s/\[(\w+)\]/$1/g;

  # 5) Capitalize first letter. But ignore leading <\w>s!
  if ($msg =~ m/^</) {
    $msg =~ s/^(<\w+>)(\w)/$1\U$2/;
  } else {
    $msg =~ s/^(\w)/\U$1/;
  }

  # 6) Capitalize first letter after every punctuation mark.
  $msg =~ s/(\.|!|\?) (\w)/$1 \U$2/g;

  # And finally say it! Or send it! Or.. we don't care, actually.
  my $caller = (caller(1))[3];
  $caller = (caller(2))[3] if $caller eq "Util::STOP";  # Useless
  GAME->message($channel, $msg, $self, $caller);
}

# Shortcut to set up a timer
sub schedule {
  my ($actor, %opts) = @_;
  GAME->schedule(-do => [$actor, delete $opts{-do}], %opts);
}

# Do we inherit from something?
sub is {
  my ($self, $what) = @_;
  return $self->isa( GAME->{Templates}{$what} );
}

# Inflation from network, file, DB, we don't care.
sub recreate {
  my $self = shift;
  GAME->{Objects}[ $self->{ID} ] = $self;
  # it already has good ol package blessed
  $self->unserialize(@_);
  return $self;
}

sub unserialize {}  # Blank deliberately

# TODO we're OK here, but work on the protocol..
# Transform an action heap into a message to share
sub act {
  my ($self, $heap) = @_;
  my $send = ["act", $self->{ID}, $heap->{Action}];
  # TODO ehh i dont like this happening.
  #while (my ($key, $val) = each %$heap) {
  #  next if $key eq "Action" or $key eq "Args";
  #  push @$send, "-$key" => $val;
  #}
  push @$send, map { is_obj($_) ? "OBJ_$_->{ID}" : $_ } @{ $heap->{Args} };
  return $send;
}

42;
