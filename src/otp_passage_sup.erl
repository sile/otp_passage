%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
%%
%% @private
-module(otp_passage_sup).

-behaviour(supervisor).

%%------------------------------------------------------------------------------
%% Application Internal API
%%------------------------------------------------------------------------------
-export([start_link/0]).

%%------------------------------------------------------------------------------
%% 'supervisor' Callback API
%%------------------------------------------------------------------------------
-export([init/1]).

%%------------------------------------------------------------------------------
%% Application Internal Functions
%%-------------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, Reason :: term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%------------------------------------------------------------------------------
%% 'supervisor' Callback Functions
%%------------------------------------------------------------------------------
init([]) ->
    Table = #{
      id      => otp_passage_capability_table,
      start   => {otp_passage_capability_table, start_link, []},
      restart => permanent
     },
    {ok, {#{}, [Table]} }.
