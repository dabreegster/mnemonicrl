package PerlRL::Client;

use strict;
use warnings;
use Util;

# Particular order >_<
BEGIN {
  bless GAME, __PACKAGE__ if ref GAME eq "HASH";
  our @ISA = ("PerlRL::Standalone");
}

# TODO tmp
sub server { 0 }
sub client { 1 }
sub fullsim { 0 }

use HexedUI::Interface; # POE bug
use POE ("Component::Client::TCP", "Filter::Reference");
use PerlRL::Standalone;
use BDSM::Map;
use Data::Dumper;

# Just set up some log stuff and delegate to standalone
sub init {
  my $game = shift;

  my $clientlog = "mrl_log";
  if (-f $clientlog) {
    my $errs = [ slurp($clientlog) ];
    $errs = "" unless @$errs;
    $game->{Errlog} = $errs;
  }

  $game->SUPER::init(@_);
}

# Get online!
sub begin {
  my $game = shift;

  # Set up the network
  POE::Component::Client::TCP->new(
    Alias         => "tcpclient",
    RemoteAddress => CFG->{Game}{Server},
    RemotePort    => CFG->{Game}{Port},
    Filter        => POE::Filter::Reference->new("Storable", 1),
    ServerInput   => sub {
      debug "blank server cmd why? TODO", return unless $_[ARG0];
      my ($cmd, @args) = @{ $_[ARG0] };
      $cmd = "cmd_$cmd";
      $game->$cmd(@args);
    },
    Connected => sub {
      # We can't do anything yet; wait for an ID and a setup command from the server
    },
    ConnectError => sub {
      UI->popup("You can't connect to the server...",
                "Unless your Internet connection is faulty, the server is probably down.
                Try again in a few moments (the server may be restarting) or later.",
                "If you continue to have problems, please ask for help (see the README)."
               );
      exit;
    },
    Disconnected => sub {
      msg err => "You've been disconnected.";
    },
    ServerError => sub {
      return if GAME->{Shutdown};
      GAME->{Shutdown} = 1;
      # popup lets POE take over again, and for whatever reason, this session spams the
      # ServerErrors. Lovely.
      UI->popup("Whoops, the server abruptly shut down!",
        "Either something broke or a new version is being deployed, try reconnecting in a few moments or give me time to work on the bug."
      );
      exit;
    },
    InlineStates => {
      sendmsg => sub {
        $_[HEAP]{server}->put($_[ARG0]);
      }
    }
  );
}

# Send a message to the server.
sub sendmsg {
  my ($self, @args) = @_;
  POE::Kernel->post("tcpclient" => sendmsg => [@args]);
}

# Send our lovely massagings of the tongue
sub chat_cb {
  my ($game, $msg) = @_;
  $game->sendmsg("chat", $msg);
}

# When we win, let's win everywhere.
sub goodcmd_cb {
  my ($game, $player, $heap) = @_;
  my $verb = $heap->{Action};
  my @args = map { is_obj($_) ? "OBJ_$_->{ID}" : $_ } @{ $heap->{Args} };
  $game->sendmsg("act", $verb, @args);
  log_this($player->id . " asking server to $verb");
}

# Upon connecting, we get a client ID
sub cmd_id {
  my ($game, $id) = @_;
  $game->{ClientID} = $id;
  msg err => "You've connected, client $id!";

  # Now send log in information
  GAME->sendmsg("login", %{ delete GAME->{Login} }, Errlog => delete GAME->{Errlog});
}

# Anytime we change maps
sub cmd_setup {
  my ($game, $dat) = @_;
  $game->{Objects} = [];   # We don't care about old stuff, it'll confuse us.
  $game->{Global} = [];
  my $map = $dat->unserialize;
  # Fix stairs; often they're added at runtime?
  $map->{_Data}{Stairs} ||= [];
  $map->stair(@$_) foreach @{ delete $map->{_Data}{Stairs} };

  log_this("Setting up map $map->{Depth}");

  # Do object reconstruction ourselves, it doesnt belong to BDSM::Map
  # Agents
  foreach (@{ $dat->{Agents} }) {
    my $agent = $_->recreate($map);
    $agent->_bliton;
  }
  
  # Map Items
  foreach (@{ $dat->{MapItems} }) {
    my $item = shift(@{$_})->recreate($map, @$_);
  }

  $game->{Global} = $dat->{Global};
  $_->recreate foreach @{ $game->{Global} };

  $game->got_player(Player);
}

# A fly sneezed. Simulate [part] of it.
sub cmd_act {
  my ($game, $id, $verb, @params) = @_;
  my $actor = GAME->{Objects}[$id];
  unless ($actor) {
    debug "we dont know of client $id, wont attempt $verb --";
    return;
  }

  my @args = map { $_ =~ s/^OBJ_// ? GAME->{Objects}[$_] : $_ } @params;

  $actor->$verb(@args);
}

# Common sense stuff
sub cmd_chat {
  my ($game, $msg) = @_;
  msg chat => $msg;
}

sub cmd_msg {
  my ($game, $id, $channel, $msg, @args) = @_;
  my $actor = GAME->{Objects}[$id];
  @args = map { GAME->{Objects}[$_] } @args;
  # TODO: if theyre out of FOV, could change it always
  $actor->saymsg(">$channel", $msg, @args);
}

sub cmd_connect {
  my ($game, $id) = @_;
  msg chat => "Client $id has connected!";
}

sub cmd_disconnect {
  my ($game, $id) = @_;
  msg chat => "Client $id has disconnected!";
}

# People joining or leaving our map only

sub cmd_join {
  my ($game, $dat) = @_;
  my $agent = $dat->recreate($game->{Map});
  $agent->_bliton;
  # Guarenteed unique names here
  msg chat => $agent->name . " has joined the map";
  UI->{Main}->refocus;
  UI->{Main}->drawme;
}

sub cmd_leave {
  my ($game, $id) = @_;
  my $agent = GAME->{Objects}[$id];
  $agent->cleanup;
  msg chat => $agent->Name . " has left the map";
}

# Server simulates stats, we just report them
sub cmd_stat {
  my ($game, $id, $stat, $value, $cap) = @_;
  my $agent = GAME->{Objects}[$id];
  if ($agent->{$stat}) {
    $agent->{$stat}->change($cap) if $agent->{$stat}->cap != $cap;
    $agent->{$stat}->mod($value);
  } else {
    debug "$stat is $value/$cap for undef agent";
  }
}

# Fuck conservation laws, stuff's popping outta da WALLS.
sub cmd_spawnstuff {
  my ($game, $y, $x, $thing) = @_;
  $thing->recreate($game->{Map}, $y, $x);
  $game->{Map}->modded($y, $x);
  UI->{Main}->drawme;
}

# TODO we nuked mapmod for lack of use besides alchemist.. and invmv

# TODO eh we're boring, surely can be moved
sub cmd_mapscript {
  my ($game, @args) = @_;
  $game->{Map}->script(@args);
}

# Inject!

package Game::StdLib::Character::Player;

{
  no warnings "redefine";
  sub PRE_lswho {}  # Nuke the Standalone one
}

sub ON_lswho {
  my ($self, $heap, @ppl) = actargs @_;
  UI->choose("Who's online?", @ppl);
}

package Game::StdLib::Character;

{
  no warnings "redefine";
  sub AFTER_changedepth {}  # Nuke the Standalone one
}

42;
