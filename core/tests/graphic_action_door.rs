//! Black-box tests for the door through which an action's `end` comes to
//! carry a graphic clip's props (format version 13, spec §11 G-34 (a)–(d),
//! (j)), through the C FFI as `ReelCore.swift` drives it: what
//! `set_action_end` stores (each prop's kind beside it, a `kinds` sent back
//! discarded), where a ramp's START comes from (the schema's current
//! default, written once), every refusal in its own sentence, removal, the
//! written key order, and the two other doors that keep an animated start —
//! `set_graphic`'s `null` and `paste_attributes`' `graphic` group. What an
//! end DOES over time is `graphic_actions.rs`'s; what a file holds is
//! `schema_v13.rs`'s.

mod common;
#[path = "common/graphic_actions.rs"]
mod fixture;

use serde_json::{json, Value};

use common::{int, Outcome};
use fixture::{
    base, clip, end, keys, project, project_with, props_at, schema, with_action, written, SEC,
};

/// Action `action`'s stored `end` on clip `id`.
fn end_of(handle: &common::Handle, id: i64) -> Value {
    clip(handle, id)["actions"][0]["end"].clone()
}

/// `set_action_end` on clip 11 with a schema of the caller's choosing.
fn end_with(action: i64, patch: Value, schema: Value) -> Value {
    json!({"op": "set_action_end", "clip": 11, "action": action, "patch": patch,
           "schema": schema})
}

fn set_graphic(props: Value, schema: Option<Value>) -> Value {
    let mut op = json!({"op": "set_graphic", "clips": [11], "patch": {"props": props}});
    if let Some(schema) = schema {
        op["schema"] = schema;
    }
    op
}

#[test]
fn a_prop_the_clip_lacks_starts_from_the_schemas_default_once() {
    let (with, action) = with_action();
    let named = with.apply(&end(action, json!({"graphic": {"props": {"extra": 9}}})));
    assert_eq!(
        end_of(&named, 11),
        json!({"graphic": {"props": {"extra": 9}, "kinds": {"extra": "number"}}})
    );
    // The default, appended after the clip's own props in the same edit.
    let order = keys(&written(&named), "/clips/0/graphic/props");
    assert_eq!(
        order,
        ["title", "size", "accent", "boxed", "align", "extra"]
    );
    assert_eq!(clip(&named, 11)["graphic"]["props"]["extra"], json!(7));
    // A later default does not move a start already written.
    let mut later = schema();
    later["extra"]["default"] = json!(10);
    let again = named.apply(&end_with(
        action,
        json!({"graphic": {"props": {"extra": 11}}}),
        later,
    ));
    assert_eq!(clip(&again, 11)["graphic"]["props"]["extra"], json!(7));
    // A colour end is stored as G-12 writes it.
    let green = with.apply(&end(
        action,
        json!({"graphic": {"props": {"accent": "rgb(0,255,0)"}}}),
    ));
    assert_eq!(
        end_of(&green, 11),
        json!({"graphic": {"props": {"accent": "#00ff00"}, "kinds": {"accent": "color"}}})
    );
}

#[test]
fn a_colour_start_is_the_default_normalised() {
    let (with, action) = with_action();
    let named = with.apply(&end(
        action,
        json!({"graphic": {"props": {"tint": "blue"}}}),
    ));
    assert_eq!(
        clip(&named, 11)["graphic"]["props"]["tint"],
        json!("#ff0000")
    );
    assert_eq!(
        end_of(&named, 11)["graphic"]["props"]["tint"],
        json!("#0000ff")
    );
}

#[test]
fn an_end_read_back_with_its_kinds_can_be_sent_again() {
    let mut two = base();
    let mut b = two["clips"][0].clone();
    b["id"] = json!(13);
    b["start"] = json!(5 * SEC);
    two["clips"].as_array_mut().expect("clips").push(b);
    let both = common::Handle::from_value(&two)
        .apply(&json!({"op": "add_action", "clip": 11, "at": SEC, "duration": SEC}))
        .apply(&json!({"op": "add_action", "clip": 13, "at": SEC, "duration": SEC}));
    let (a, b) = (
        int(&clip(&both, 11), "/actions/0/id"),
        int(&clip(&both, 13), "/actions/0/id"),
    );
    let patch = json!({"graphic": {"props": {"size": 129, "accent": "#ffffff"}}});
    let on_a = both.apply(&end(a, patch));
    let read_back = end_of(&on_a, 11);
    assert!(read_back["graphic"]["kinds"].is_object(), "{read_back}");
    let on_b = on_a.apply(&json!({"op": "set_action_end", "clip": 13, "action": b,
                                  "patch": read_back, "schema": schema()}));
    assert_eq!(end_of(&on_b, 13), end_of(&on_b, 11));
    // A `kinds` alone names no prop, whatever it holds: nothing changes.
    assert!(matches!(
        on_a.try_apply(&end(a, json!({"graphic": {"kinds": {"size": "color"}}}))),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn every_refusal_names_its_prop_in_its_own_sentence() {
    let (with, action) = with_action();
    let error = |patch: Value| with.errors(&end(action, patch));
    let props = |props: Value| json!({"graphic": {"props": props}});
    assert_eq!(
        error(json!({"graphic": {"tint": 1}})),
        "unknown key \"graphic.tint\" in an action end patch"
    );
    assert_eq!(
        error(json!({"graphic": {"props": 5}})),
        "graphic.props must be a json object, not 5"
    );
    assert_eq!(
        error(props(json!({"logo": "logo.png"}))),
        "graphic.props.logo is an asset; an action does not animate an image — set it with \
         set_graphic"
    );
    assert_eq!(
        error(props(json!({"nope": 1}))),
        "unknown key \"graphic.props.nope\" in an action end patch"
    );
    for layer in ["name", "width", "height", "in", "length"] {
        assert_eq!(
            error(json!({"graphic": {(layer): 1}})),
            format!("graphic.{layer} is not an animation target; an action animates graphic.props")
        );
    }
    assert_eq!(
        with.errors(
            &json!({"op": "set_action_end", "clip": 11, "action": action,
                            "patch": props(json!({"size": 100}))})
        ),
        "graphic.props.size needs its module's schema to animate, and none came with the op"
    );
    let on_text = with.apply(&json!({"op": "add_action", "clip": 12, "at": 0}));
    let text_action = int(&clip(&on_text, 12), "/actions/0/id");
    assert_eq!(
        on_text.errors(
            &json!({"op": "set_action_end", "clip": 12, "action": text_action,
                               "patch": props(json!({"size": 100})), "schema": schema()})
        ),
        "clip 12 is not a graphic clip"
    );
    assert_eq!(
        error(props(json!({"size": "big"}))),
        "graphic.props.size must be a number, not \"big\""
    );
    assert_eq!(
        error(props(json!({"size": 500}))),
        "graphic.props.size must be between 0 and 400, not 500"
    );
    assert_eq!(
        with.errors(
            &json!({"op": "set_action_end", "clip": 11, "action": action,
                            "patch": {}, "off": ["graphic.props"], "schema": schema()})
        ),
        "graphic props cannot be keyed off; name the value a prop ends at in patch"
    );
    assert_eq!(
        error(json!({"graphic": 5})),
        "graphic in an action end patch must be a json object, not 5"
    );
}

#[test]
fn motion_and_words_keep_their_sentences() {
    let (with, action) = with_action();
    let on = |patch: Value, off: Value| {
        json!({"op": "set_action_end", "clip": 11, "action": action, "patch": patch,
               "off": off, "schema": schema()})
    };
    let motion = "video.motion is not an animation target";
    let words = "text.words is not an animation target";
    assert_eq!(
        with.errors(&on(json!({"video": {"motion": null}}), json!([]))),
        motion
    );
    assert_eq!(
        with.errors(&on(json!({"text": {"words": []}}), json!([]))),
        words
    );
    assert_eq!(with.errors(&on(json!({}), json!(["video.motion"]))), motion);
    assert_eq!(with.errors(&on(json!({}), json!(["text.words"]))), words);
}

#[test]
fn a_null_removes_a_prop_and_its_kind_and_an_empty_props_is_an_identity() {
    let (with, action) = with_action();
    let named = with.apply(&end(
        action,
        json!({"graphic": {"props": {"extra": 9, "size": 100}}}),
    ));
    let removed = named.apply(&end(action, json!({"graphic": {"props": {"extra": null}}})));
    assert_eq!(
        end_of(&removed, 11),
        json!({"graphic": {"props": {"size": 100}, "kinds": {"size": "number"}}})
    );
    let dropped = named.apply(&end(action, json!({"graphic": null})));
    assert_eq!(end_of(&dropped, 11), json!({}));
    let dropped = named.apply(&end(action, json!({"graphic": {"props": null}})));
    assert_eq!(end_of(&dropped, 11), json!({}));
    assert!(matches!(
        named.try_apply(&end(action, json!({"graphic": {"props": {}}}))),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn a_removal_keeps_the_other_keys_in_their_order() {
    let (with, action) = with_action();
    let video = with.apply(&end(
        action,
        json!({"video": {"opacity": 0.5, "x": 10, "y": 20}}),
    ));
    let pruned = video.apply(&end(action, json!({"video": {"opacity": null}})));
    assert_eq!(
        keys(&written(&pruned), "/clips/0/actions/0/end/video"),
        ["x", "y"]
    );

    let graphic = with.apply(&end(
        action,
        json!({"graphic": {"props": {"title": "B", "size": 100, "accent": "#ffffff"}}}),
    ));
    let pruned = graphic.apply(&end(action, json!({"graphic": {"props": {"title": null}}})));
    let text = written(&pruned);
    assert_eq!(
        keys(&text, "/clips/0/actions/0/end/graphic/props"),
        ["size", "accent"]
    );
    assert_eq!(
        keys(&text, "/clips/0/actions/0/end/graphic/kinds"),
        ["size", "accent"]
    );
}

#[test]
fn set_graphics_null_keeps_an_animated_props_default() {
    let (with, action) = with_action_on_size(100);
    let animated = with.apply(&end(action, json!({"graphic": {"props": {"size": 129}}})));
    // With the schema: the animated `size` takes its default, in its slot.
    let kept = animated.apply(&set_graphic(json!({"size": null}), Some(schema())));
    assert_eq!(clip(&kept, 11)["graphic"]["props"]["size"], json!(64));
    let order = keys(&written(&kept), "/clips/0/graphic/props");
    assert_eq!(order, ["title", "size", "accent", "boxed", "align"]);
    // At the default already, the same `null` changes nothing.
    assert!(matches!(
        kept.try_apply(&set_graphic(json!({"size": null}), Some(schema()))),
        Ok(Outcome::Identity)
    ));
    // Without a schema it removes; an un-animated key is removed either way.
    let gone = animated.apply(&set_graphic(json!({"size": null}), None));
    assert!(clip(&gone, 11)["graphic"]["props"].get("size").is_none());
    let title = animated.apply(&set_graphic(json!({"title": null}), Some(schema())));
    assert!(clip(&title, 11)["graphic"]["props"].get("title").is_none());
}

/// [`with_action`] on a clip whose `size` is `size`.
fn with_action_on_size(size: i64) -> (common::Handle, i64) {
    fixture::with_action_on(&project_with("size", json!(size)))
}

#[test]
fn a_paste_keeps_an_animated_start_in_its_slot() {
    let (with, action) = with_action();
    let animated = with.apply(&end(action, json!({"graphic": {"props": {"size": 129}}})));
    let mut source = clip(&project(), 11);
    source["graphic"]["props"] = json!({"title": "P", "accent": "#00000000", "align": "left"});
    source["track"] = json!(0);
    let payload = json!({"clips": [source], "media": [], "nests": []});
    let pasted = animated.apply(&json!({"op": "paste_attributes", "clips": [11],
                                        "payload": payload, "groups": ["graphic"]}));
    let props = clip(&pasted, 11)["graphic"]["props"].clone();
    assert_eq!(
        keys(&written(&pasted), "/clips/0/graphic/props"),
        ["title", "size", "accent", "align"]
    );
    assert_eq!(props["size"], json!(64));
    assert_eq!(props["title"], json!("P"));
    // `boxed`, which no action names and the payload lacks, is gone.
    assert!(props.get("boxed").is_none(), "{props}");
    assert_eq!(props_at(&pasted, SEC + SEC / 2)["size"], json!(96.5));
}
