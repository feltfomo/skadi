# _lib/ownerships/axes.nix
#
# The set-axis value type (a polarity set) plus host + user registered on the
# engine -- the first two axes, and the only two shipped so far. This is the one
# file allowed to name host/user; the engine below never does. A set axis carries
# a polarity set and reads an entity's identity (ctx.<axis>.name); a predicate
# (`when`) axis could be added later with no engine change to slot in.
_:
let
  inherit (builtins) elem filter;

  # a polarity set: { tag = "include" | "exclude"; set = [name]; }. include A is
  # exactly A; exclude A is everyone but A; exclude [] is global -- the identity.
  mk = tag: set: { inherit tag set; };
  include = mk "include";
  exclude = mk "exclude";
  global = exclude [ ];

  # plain set ops on name lists, order-preserving so merges stay deterministic.
  inter = a: b: filter (x: elem x b) a;
  diff = a: b: filter (x: !(elem x b)) a;
  union = a: b: a ++ filter (x: !(elem x a)) b;

  # meet of two polarity sets -- deliberately roster-INDEPENDENT, so "globally
  # owned" is expressible without materializing the fleet:
  #   include A ,, include B = include (A n B)
  #   exclude A ,, exclude B = exclude (A u B)
  #   include A ,, exclude B = include (A \ B)
  # exclude [] is the two-sided identity, which is why it is top.
  meet =
    a: b:
    if a.tag == "include" && b.tag == "include" then
      include (inter a.set b.set)
    else if a.tag == "exclude" && b.tag == "exclude" then
      exclude (union a.set b.set)
    else
      let
        inc = if a.tag == "include" then a else b;
        exc = if a.tag == "include" then b else a;
      in
      include (diff inc.set exc.set);

  # materialize a polarity set against the roster's members for this axis.
  # include keeps the members it names (a typo collapses to [] -> impossible);
  # exclude is the complement, so a host added to the roster later is owned for
  # free -- the openness win over a frozen enumeration.
  resolveMembers = members: v: if v.tag == "include" then inter v.set members else diff members v.set;

  # a set axis over one roster dimension. `key` is the ctx attr it reads
  # (ctx.${key}.name); `members` is the roster's known names for the axis.
  # narrow/top never touch members -- only satisfiable/select consult the roster.
  mkSetAxis =
    {
      key,
      members ? [ ],
    }:
    {
      top = global;
      narrow = meet;
      satisfiable = v: resolveMembers members v != [ ];
      select = v: ctx: elem ctx.${key}.name (resolveMembers members v);
    };
in
{
  inherit
    include
    exclude
    global
    mkSetAxis
    ;

  # host + user. members come from the roster, stubbed here for now; the real
  # den-backed roster wires through _lib/den.nix later in the same shape.
  registry =
    {
      hosts ? [ ],
      users ? [ ],
    }:
    {
      host = mkSetAxis {
        key = "host";
        members = hosts;
      };
      user = mkSetAxis {
        key = "user";
        members = users;
      };
    };
}
