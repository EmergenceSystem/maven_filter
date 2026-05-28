%%%-------------------------------------------------------------------
%%% @doc Maven Central package search agent.
%%%
%%% Searches Maven Central for Java/JVM artifacts and returns embryos
%%% with groupId, artifactId, latest version, and packaging type.
%%%
%%% API: https://search.maven.org/solrsearch/select?q={query}&rows=10&wt=json
%%%
%%% Handler contract: handle/2 (Body, Memory) -> {RawList, Memory}.
%%% @end
%%%-------------------------------------------------------------------
-module(maven_filter_app).
-behaviour(application).

-export([start/2, stop/1]).
-export([handle/2, base_capabilities/0]).

-define(SEARCH_URL,
    "https://search.maven.org/solrsearch/select?rows=10&wt=json&q=").

%%====================================================================
%% Capability cascade
%%====================================================================

-spec base_capabilities() -> [binary()].
base_capabilities() ->
    em_filter:base_capabilities() ++ [<<"maven">>, <<"java">>,
                                      <<"jvm">>, <<"kotlin">>,
                                      <<"scala">>, <<"packages">>].

%%====================================================================
%% Application lifecycle
%%====================================================================

start(_Type, _Args) ->
    case maven_filter_sup:start_link() of
        {ok, Pid} ->
            ok = start_pop_and_http(),
            {ok, Pid};
        Error ->
            Error
    end.

stop(_State) ->
    catch cowboy:stop_listener(maven_filter_query_listener),
    catch em_pop_sup:stop_node(maven_filter),
    ok.

%%====================================================================
%% Internal
%%====================================================================

start_pop_and_http() ->
    PopPort   = application:get_env(maven_filter, pop_port,   9464),
    QueryPort = application:get_env(maven_filter, query_port, 9465),
    Seeds     = application:get_env(maven_filter, pop_seeds,  []),
    Vec = em_filter_vec:from_capabilities(base_capabilities()),
    catch em_pop_sup:stop_node(maven_filter),
    catch cowboy:stop_listener(maven_filter_query_listener),
    {ok, PopPid} = em_pop_sup:start_node(maven_filter, #{
        port            => PopPort,
        query_port      => QueryPort,
        vector          => Vec,
        max_peers       => 100,
        gossip_interval => 5_000
    }),
    lists:foreach(
        fun({H, P}) -> catch em_pop_node:add_peer(PopPid, H, P) end,
        Seeds),
    Dispatch = cowboy_router:compile([
        {'_', [{"/agent/query", em_filter_http,
                #{server => maven_filter_server}}]}
    ]),
    {ok, _} = cowboy:start_clear(maven_filter_query_listener,
                                  [{port, QueryPort}],
                                  #{env => #{dispatch => Dispatch}}),
    logger:notice("[maven_filter] gossip port ~w  query port ~w",
                  [PopPort, QueryPort]),
    ok.

handle(Body, Memory) when is_binary(Body) ->
    {generate_embryo_list(Body), Memory};
handle(_Body, Memory) ->
    {[], Memory}.

%%====================================================================
%% Search and processing
%%====================================================================

generate_embryo_list(JsonBinary) ->
    {Query, Timeout} = extract_params(JsonBinary),
    fetch_results(Query, Timeout).

extract_params(JsonBinary) ->
    try json:decode(JsonBinary) of
        Map when is_map(Map) ->
            Query = binary_to_list(maps:get(<<"value">>, Map,
                        maps:get(<<"query">>, Map, <<"">>))),
            Timeout = to_timeout(maps:get(<<"timeout">>, Map, undefined)),
            {Query, Timeout};
        _ ->
            {binary_to_list(JsonBinary), 10}
    catch
        _:_ -> {binary_to_list(JsonBinary), 10}
    end.

fetch_results("", _) -> [];
fetch_results(Query, Timeout) ->
    Url = lists:flatten(io_lib:format("~s~s", [?SEARCH_URL, uri_string:quote(Query)])),
    case httpc:request(get, {Url, []},
                       [{timeout, Timeout * 1000},
                        {ssl, [{verify, verify_none}]}],
                       [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} -> parse_results(Body);
        _                            -> []
    end.

parse_results(JsonBin) ->
    try json:decode(JsonBin) of
        #{<<"response">> := #{<<"docs">> := Docs}} when is_list(Docs) ->
            lists:filtermap(fun build_embryo/1, Docs);
        _ -> []
    catch
        _:_ -> []
    end.

build_embryo(Doc) ->
    G       = maps:get(<<"g">>,             Doc, <<"">>),
    A       = maps:get(<<"a">>,             Doc, <<"">>),
    Version = maps:get(<<"latestVersion">>, Doc, <<"">>),
    Pack    = maps:get(<<"p">>,             Doc, <<"jar">>),
    case {G, A} of
        {<<"">>, _} -> false;
        {_, <<"">>} -> false;
        _ ->
            Id  = iolist_to_binary([G, ":", A]),
            Url = iolist_to_binary([
                "https://search.maven.org/artifact/", G, "/", A
            ]),
            Resume = format_resume(G, Version, Pack),
            {true, #{<<"properties">> => #{
                <<"url">>       => Url,
                <<"title">>     => Id,
                <<"resume">>    => Resume,
                <<"version">>   => Version,
                <<"source">>    => <<"maven.org">>
            }}}
    end.

format_resume(Group, Version, Pack) ->
    G = bin(Group),
    V = case Version of <<>> -> ""; _ -> " v" ++ binary_to_list(Version) end,
    P = case Pack of <<>> -> ""; _ -> " (" ++ binary_to_list(Pack) ++ ")" end,
    list_to_binary(G ++ V ++ P).

%%====================================================================
%% Helpers
%%====================================================================

bin(B) when is_binary(B) -> binary_to_list(B);
bin(_)                   -> "".

to_timeout(undefined)            -> 10;
to_timeout(T) when is_integer(T) -> T;
to_timeout(T) when is_binary(T)  ->
    try binary_to_integer(T) catch _:_ -> 10 end;
to_timeout(_) -> 10.
