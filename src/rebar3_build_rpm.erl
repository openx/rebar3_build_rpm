-module (rebar3_build_rpm).

% I don't feel like have a dependency to get the specs and callbacks definitions
% % but this module implements the provider behavior
% %-behaviour (provider).

-export ([init/1,
          do/1,
          format_error/1]).

-define(PROVIDER, build_rpm).
-define(DEPS, [tar]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
  State1 = rebar_state:add_provider(State,
             providers:create([{name, ?PROVIDER},
                               {module, ?MODULE},
                               {bare, true},
                               {deps, ?DEPS},
                               {example, "rebar3 build_rpm"},
                               {short_desc, "Build rpm of release build of project."},
                               {desc, "Build rpm of release build of project."},
                               {opts, []}])),
  {ok, State1}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->

  {ok, {Name, Vsn}} = find_name_and_vsn_from_relx (State),

  {ok, TarFile} = find_tar_file (State, {Name, Vsn}),

  {ok, PkgConfig} = find_package_config_from_relx (Name, State),

  RootPath = filename:join ([rebar_dir:base_dir(State), "rpm"]),
  % build will represent / on the target system filesystem, in other
  % words any files or directories under this will be placed under /
  % on the target system
  BuildPath = filename:join(RootPath, "build"),

  % we want to unpack in a prefixed directory then with the release name
  Prefix = find_in_package_config (prefix, PkgConfig, "usr/lib64"),
  ReleasePath = filename:join ([BuildPath] ++ [Prefix] ++ [Name]),
  % build that path
  mkdir_p (ReleasePath),
  % untar the release into that directory
  erl_tar:extract(TarFile, [{cwd,ReleasePath}, compressed]),

  % if there is a slash path in the release, we'll move everything out
  % of that directory into the top-level one
  ReleaseSlashPath = filename:join (ReleasePath,"slash"),

  % we move all the files which are under slash directly into the build
  % directory.  This is not a simple move as it actually creates directories
  % which don't exist, moves files and removes the old directories.
  %
  % NOTE: the [$/] is necessary because of the fold_dir from epm which I'm 
  % using.  It could probably be gotten rid of with a little effort
  move_from_slash (ReleaseSlashPath ++ [$/], BuildPath),

  % at this point we should have a directory layout to match our
  % target system
  file:set_cwd (BuildPath),
  BuildPaths = ls_dir (BuildPath),

  % remove any paths which don't contain the Name of the release.  This is
  % probably something which should be made optional, but we'll see if we
  % ever need to.
  ExcludePaths = determine_exclude_dirs (BuildPath ++ [$/], Name),
  ExcludeArgs = construct_arg_list ("--exclude-dir",ExcludePaths),
  % set up dependency args if they exist
  DependsArgs =
    construct_arg_list ("--depends",
                        string:tokens(
                          find_in_package_config (depends, PkgConfig, ""),
                          ",")),
  % set up path user:group overrides if they exist
  OverridesArgs =
    construct_arg_list ("--user-group-override",
                        string:tokens(
                          find_in_package_config (overrides, PkgConfig, ""),
                          ",")),

  % construct our package hooks if they exist
  PkgHooks = construct_pkg_hooks (PkgConfig, ReleasePath),

  PkgName = find_in_package_config (name, PkgConfig, Name),
  PkgVersion = find_in_package_config (version, PkgConfig, Vsn),
  % check for an environment variable specifying the build number, otherwise
  % check the pkg.config file, otherwise default to "1"
  PkgIteration =
    os:getenv("REBAR3_BUILD_RPM_BUILD_NUMBER",
              find_in_package_config (iteration, PkgConfig, "1")),
  PkgArch = "x86_64",
  rebar3_build_rpm_epm:main(
    ["-f",           % overwrite any existing rpm
     "-s", "dir",    % package input type (e.g. directory)
     "-t", "rpm",    % build an rpm
     "-a", PkgArch, % is there any other?
     % name of package (defaults to release name)
     "-n", PkgName,
     % version of package (defaults to release version)
     "-v", PkgVersion,
     % release of the package (defaults to 1)
     "--iteration", PkgIteration,
     "--url", find_in_package_config (url, PkgConfig, "(unknown)"),
     "--summary", find_in_package_config (summary, PkgConfig, "(unknown)"),
     "--description", find_in_package_config (description, PkgConfig, "(unknown)"),
     "--vendor", find_in_package_config (vendor, PkgConfig, "(unknown)"),
     "--license", find_in_package_config (license, PkgConfig, "(unknown)"),
     "--maintainer", find_in_package_config (maintainer, PkgConfig, "(unknown)")
    ]
    ++ DependsArgs
    ++ OverridesArgs
    ++ ExcludeArgs
    ++ PkgHooks
    ++ BuildPaths
  ),
  RpmFile = PkgName++"-"++PkgVersion++"-"++PkgIteration++"."++PkgArch++".rpm",
  RpmSourcePath = filename:join(BuildPath, RpmFile),
  RpmDestPath = filename:join(RootPath, RpmFile),
  file:rename (RpmSourcePath, RpmDestPath),
  rebar_file_utils:rm_rf (BuildPath),
  rebar_log:log (info, "rpm ~s successfully created!~n",[RpmDestPath]),
  {ok, State}.

-spec format_error(any()) -> iolist().
format_error(Reason) ->
  io_lib:format("~p", [Reason]).

find_name_and_vsn_from_relx (State) ->
  Relx = rebar_state:get(State, relx, []),
  case lists:keyfind (release, 1, Relx) of
    {release,{Name, Vsn},_} -> {ok, {atom_to_list(Name), Vsn}};
    false -> {error, {?MODULE, no_relx_config}}
  end.

find_tar_file (State, {Name, Vsn}) ->
  Base = rebar_dir:base_dir(State),
  % this is just where we expect the tar file to be located,
  % it may or may not be there or break in future versions of
  % rebar?
  TarDir = filename:join(Base, "rel"),
  % tar seems to be under 'rel' then under the release name, then
  % with the filename <release>-<version>.tar.gz
  TarFile = filename:join([TarDir, Name, Name++"-"++Vsn++".tar.gz"]),
  case file:read_file_info (TarFile) of
    {ok, _} -> {ok, TarFile};
    _ -> {error, {?MODULE, no_tar_file}}
  end.

find_package_config_from_relx (Name, State) ->
  Relx = rebar_state:get(State, relx, []),
  case lists:keyfind (pkg_config, 1, Relx) of
    {pkg_config, ConfigFile} ->
      Base = rebar_dir:base_dir(State),
      % this is just where we expect the config file to be located,
      % it may or may not be there or break randomly, but hopefully not
      ConfigFilePath = filename:join ([Base, "rel", Name, ConfigFile]),
      case file:consult(ConfigFilePath) of
        {ok, Config} ->
          {ok, Config};
        {error, E} -> {error, {?MODULE, E}}
      end;
    false ->
      {error, {?MODULE, no_pkg_config}}
  end.

find_in_package_config (Key, PkgConfig, Default) ->
  case lists:keyfind (Key, 1, PkgConfig) of
    {_, V} -> V;
    false -> Default
  end.

% if the directory list of the form
%  [ "foo", "bar", "baz" ]
% I want to filename:join/1 it, so to differentiate this from the
% case where I have mkdir_p("foo"), I need to check for a nested
% list of at least one character, thus [[_|_]|_]
mkdir_p (Dir = [[_|_]|_]) when is_list (Dir) ->
  mkdir_p (filename:join (Dir));
mkdir_p (Dir) ->
  % ensure_dir only seemed to create all but the final level of directories
  % so by adding an extra token you get what you want
  filelib:ensure_dir (filename:join ([filename:absname(Dir), "token"])).

ls_dir (Dir) ->
  case file:list_dir_all (Dir) of
    {error, _} -> [];
    {ok, F} -> F
  end.

move_from_slash (SlashPath, DestinationRoot) ->
  % recursively move all files from under slash into the destination, keeping
  % track of directories
  Directories =
    rebar3_build_rpm_epm:fold_dir (SlashPath,
      fun (File, Acc) ->
        Relative = remove_prefix (SlashPath, File),
        Dest = filename:join([DestinationRoot, Relative]),
        case filelib:is_dir (File) of
          true -> mkdir_p (Dest), [Relative | Acc];
          false -> file:rename (File, Dest), Acc
        end
      end,
      []),
  % now sort directories by length and remove based on longest
  lists:foreach (
    fun (D) ->
      file:del_dir (filename:join([SlashPath,D]))
    end,
    lists:sort (fun (A, B) -> length(A) >= length(B) end, Directories)
  ).

% Create a list of paths under Path which don't contain Name
determine_exclude_dirs (Path, Name) ->
  Excludes =
    rebar3_build_rpm_epm:fold_dir (Path,
                  fun (File, Acc) ->
                    case filelib:is_dir (File) of
                      true ->
                        Relative = remove_prefix (Path, File),
                        case re:run (Relative, Name, [{capture,none}]) of
                          match -> Acc;
                          nomatch -> [Relative | Acc]
                        end;
                      false ->
                        Acc
                    end
                  end,
                  []),
  lists:reverse (Excludes).

remove_prefix ([],R) -> R;
remove_prefix ([C|R1],[C|R2]) -> remove_prefix (R1, R2).

construct_arg_list (_, []) -> [];
construct_arg_list (ArgKey, L) ->
  lists:foldr (fun (D,A) ->
                 lists:append ([ArgKey, D],A)
               end,
               [],
               L).

construct_pkg_hooks (PkgConfig, ReleasePath) ->
  lists:foldl (
    fun ({ConfigKey, EpmKey}, A) ->
      case find_in_package_config (ConfigKey, PkgConfig, undefined) of
        undefined -> A;
        Path -> [ EpmKey, filename:join (ReleasePath, Path) | A ]
      end
    end,
    [],
    [ {pre_install, "--pre-install"},
      {post_install, "--post-install"},
      {pre_uninstall, "--pre-uninstall"},
      {post_uninstall, "--post-uninstall"}
    ]
  ).
