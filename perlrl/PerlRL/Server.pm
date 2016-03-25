package PerlRL::Server;

use strict;
use warnings;
use Util;

# Particular order >_<
BEGIN {
  bless GAME, __PACKAGE__ if ref GAME eq "HASH";
  our @ISA = ("PerlRL::Component::Game");
}

use POE ("Component::Server::TCP", "Filter::Reference");
use PerlRL::Component::Game;

# TODO tmp
sub fullsim { 1 }
sub server { 1 }
sub client { 0 }

# Set up stuff
sub init {
  my ($game, $load) = @_;

  print STDERR "-" x 80 . "\n";
  log_this("PerlRL server booting up!");

  $game->content($load);  # Oh, and load the game content. Minor detail ;)

  # Set up the server
  POE::Component::Server::TCP->new(
    Alias        => "tcpserver",
    Port         => CFG->{Game}{Port},
    ClientFilter => POE::Filter::Reference->new("Storable", 1),
    ClientConnected => sub {
      my $client = $_[SESSION]->ID;
      GAME->sendto($client, ["id", $client]);
      # Wait for the client to log in
    },
    # I don't know which one will be called first
    ClientDisconnected => sub {
      $poe_kernel->yield("handle_disconnect");
    },
    ClientError => sub {
      $poe_kernel->yield("handle_disconnect");
    },
    ClientInput => sub {
      my $client = $_[SESSION]->ID;
      my @input = @{ $_[ARG0] };
      my $cmd = shift @input;
      unshift @input, $_[HEAP]->{remote_ip} if $cmd eq "login";
      $cmd = "cmd_$cmd";
      $game->$cmd($client, @input);
    },
    InlineStates => {
      sendmsg => sub {
        $_[HEAP]{client}->put($_[ARG0]);
      },
      handle_disconnect => sub {
        my $client = $_[SESSION]->ID;
        return unless GAME->{Clients}{$client};
        my $agent = GAME->{Clients}{$client};
        my $name = $agent->Name;
        log_this("LOGOUT) $name (client $client)");
        print STDERR "$name quit\n";
        $agent->cleanup;
        $_[KERNEL]->yield("shutdown");
        unless ($agent->{Dead}) {
          GAME->share($client, "global", "broadcast", ["disconnect", $agent->{ClientID}]);
          GAME->share($client, "local", "broadcast", ["leave", $agent->{ID}]);
        }
        delete GAME->{Clients}{$client};
        $agent->{Dead} = 1; # so monsters give it a rest
      }
    }
  );
}

# Just start POE
sub start {
  $poe_kernel->run;
}

# Make a new person
sub cmd_login {
  my ($game, $client, $ip, %dat) = @_;

  my $errlog = delete $dat{Errlog};
  log_this("LOGIN) $dat{Name} $ip");
  log_this("CERR) claiming to be $dat{Name} now. sent:\n" . join("", @$errlog)) if $errlog;
  print STDERR "$dat{Name} joined!\n";

  # Spawn their character on the map.
  my $newbie = GAME->make(delete $dat{Class},
    Map        => GAME->{Levels}{Start},
    ClientID   => $client,
    DontShare  => 1,
    Level      => 1,
    %dat
  );
  delete $newbie->{DontShare};  # Can't share actions before it's created
  GAME->{Clients}{$client} = $newbie;

  # Tell the new client what's happenin' up in this shiz-town.
  GAME->sendto($client, ["setup", $newbie->{Map}->serialize($client)]);

  # And tell everybody else about this newb -- but adding him to map is separate
  GAME->share($client, "global", "broadcast", ["connect", $client]);
  GAME->share($client, "local", "broadcast", ["join", $newbie->serialize]);
}

# Spread the gospel message
sub cmd_chat {
  my ($game, $client, $saywhat) = @_;
  my $msg = GAME->{Clients}{$client}{Name};
  debugs "CHAT) $msg: $saywhat";
  log_this("CHAT) $msg: $saywhat");
  if ($saywhat =~ s#^/me ##) {
    $msg = "* $msg $saywhat";
  } else {
    $msg .= ": $saywhat";
  }
  $game->share($client, "global", "all", ["chat", $msg]);
}

# DO SOMETHING. And tell them about it.
sub cmd_act {
  my ($game, $client, $verb, @raw_args) = @_;
  my $actor = $game->{Clients}{$client};
  return if $actor->{Dead};  # Sort of a race condition; too late, mates TODO ehh

  # Recreate the arg list
  my @args = map {
    $_ =~ s/^OBJ_// ? ($game->{Objects}[$_] // die "dont have obj $_\n") : $_
  } @raw_args;

  $actor->$verb(@args);   # A hook in _do_act will broadcast this action.

  # TODO old turn-based junk was here. eh.
}

# Share some message with a group.
sub share {
  my ($self, $sender, $scope, $inclusive, $msg) = @_;
  die "bad scope" unless $scope eq "local" or $scope eq "global";
  die "bad inclusiveity" unless $inclusive eq "broadcast" or $inclusive eq "all";

  $sender = GAME->{Clients}{$sender} unless ref $sender;
  if (is_obj($sender) and $sender->{DontShare}) {
    log_this("Whoa, don't share yet -- " . $sender->id);
    return;
  }

  # Scope = "global" (all) / "local" (map)
  my $depth;
  if ($scope eq "local") {
    $depth = $sender->{Aggregate}{Map}{Depth} if is_obj($sender);
    $depth = $sender->{Depth} if ref $sender and $sender->isa("BDSM::Map");
    debug("no map depth, but local thing to share?!", $msg), return unless $depth;
  }

  my @recips = values %{ $self->{Clients} };
  foreach my $client (@recips) {
    next if $scope eq "local" and $client->{Aggregate}{Map}{Depth} ne $depth;
    # Inclusive = "broadcast" (everyone except sender) vs "all"
    next if $inclusive eq "broadcast" and $client->{ClientID} == $sender->{ClientID};
    $self->sendto($client->{ClientID}, $msg);
  }
}

# Actually send a message to a specific client.
sub sendto {
  my ($self, $client, $msg) = @_;
  unless (ref $msg) {
    debug "trying to broadcast non-reference", $msg;
    return;
  }
  GAME->{Msg} = $msg; # To dump if we die
  $poe_kernel->post($client, sendmsg => $msg);
}

# Distribute it, depending on where it occurs
sub message {
  my ($self, $channel, $msg, $obj, $from) = @_;
  $from =~ s/^.*:://;
  # Client simulates On and After themselves... but only fullsim will do battle stuff since
  # it involves random numbers.
  return if $from =~ m/^(ON|AFTER)_/ and $channel ne "battle";
  $self->share($obj, "local", "all", ["msg", $obj->{ID}, $channel, $msg]);
}

# Something's happening, so we may need to broadcast.
sub act_cb {
  my ($self, $stage, $actor, $heap) = @_;
  return unless $stage eq "ON";
  # Broadcast so that both client and server do the action at the same time, supposedly
  # TODO use heap to know to do something else
  my $where = $actor->{Global} ? "global" : "local";
  $self->share($actor, $where, "all", $actor->act($heap))
}

sub dbug_cb {
  my ($game, $err) = @_;
  debugs $err;
}

# We don't have much to inject, really

package Game::StdLib::Character;

sub AFTER_changedepth {
  my ($self, $heap) = actargs @_;

  # Bye bye... (gotta fix the map :P)
  my $map = $self->{Map};
  $self->{Map} = $heap->{OldMap};
  GAME->share($self, "local", "broadcast", ["leave", $self->{ID}]);
  $self->{Map} = $map;
  
  # Hello!
  GAME->share($self, "local", "broadcast", ["join", $self->serialize]);
  
  # And take care of that client.
  GAME->sendto($self->{ClientID}, ["setup", $map->serialize]) if $self->{ClientID};
  
  log_this($self->name . " going to $map->{Depth}");
}

package Game::StdLib::Character::Monster;

sub WhenCorpse {
  my ($self, $corpse) = @_;
  GAME->share(
    $self, "local", "all", ["spawnstuff", $self->{Y}, $self->{X}, $corpse->serialize]
  );
}

package Game::StdLib::Character::Player;

sub BEFORE_lswho {
  my ($self, $heap) = actargs @_;
  foreach my $client (values %{ GAME->{Clients} }) {
    push @{ $heap->{Args} }, $client->Name . ", a $client->{Gender} " . $client->type . ". At $client->{Y}, $client->{X} on $client->{Map}{Depth}";
  }
  GAME->sendto($self->{ClientID}, $self->act($heap));
  return STOP;
}

# Really no good way to augment this, so just redefine it
{
  no warnings "redefine";
  sub BEFORE_journal {
    my ($self, $heap) = actargs @_;
    @{ $heap->{Args} } = keys %{ $self->{Journal} };
    return STOP($self, "You don't have any journal entries yet; go explore!") unless @{ $heap->{Args} };
    GAME->sendto($self->{ClientID}, $self->act($heap));
    return STOP;
  }
}

# Only if they have a ClientID
sub human_control {
  my $self = shift;
  return defined($self->{ClientID});
}

sub AFTER_devmode {
  my ($self, $heap, $cmd, @args) = actargs @_;
  if ($cmd eq "item") {
    my ($new, $y, $x) = @{ $heap->{Made} };
    GAME->share($self, "local", "all", ["spawnstuff", $y, $x, $new->serialize]);
  } elsif ($cmd eq "char") {
    my ($new) = @{ $heap->{Made} };
    GAME->share($self, "local", "all", ["join", $new->serialize]);
  }
}

package Game::Stat;

sub modded {
  my $stat = shift;
  return if $stat->{Name} eq "HP" and $stat->{Now} <= 0; # Dead, don't care
  my $owner = GAME->{Objects}[ $stat->{Owner} ];
  unless ($owner->{ID}) {
    debug [$stat, "is floating..."];
    return;
  }
  GAME->share(
    $owner, "local", "all", ["stat", $owner->{ID}, $stat->{Name}, $stat->{Now}, $stat->{Cap}]
  );
}

42;
