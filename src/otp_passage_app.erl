%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
%%
%% @private
-module(otp_passage_app).

-behaviour(application).

%%------------------------------------------------------------------------------
%% 'application' Callback API
%%------------------------------------------------------------------------------
-export([start/2, stop/1]).

%%------------------------------------------------------------------------------
%% 'application' Callback Functions
%%------------------------------------------------------------------------------
start(_StartType, _StartArgs) ->
    otp_passage_sup:start_link().

stop(_State) ->
    ok.
