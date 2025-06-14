/*---------------------------------------------------------------------------
  Copyright 2013 Daan Leijen, Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Attibute operations: parsing, transform text, expand keys, etc.
module attributes

import std/regex
import std/dict
import std/string
import common
import entity
import expression

public function parseAttrs( attrStr : string, elemName : string = "", source : string = "" ) : attrs {
  unsafeTotal {
    // println("parsing attributes: \n attrStr: " + attrStr + "\nsource: " + source)
    if (attrStr == "" && elemName == "" && source=="") return attrsNone
    val attrs0 = Attrs() // source=source,classes=if (className=="") then [] else [className])
    val ret = attrs0.extendAttrs( (if (elemName!="") then "elem:'" + elemName + "'; " else "") + attrStr, source )
    // println("after parsing: " + attrs0.debugAttrs)
    ret
  }
}

public function mergeDefault( attrs : attrs, def : attrs ) : attrs {
  def.extendAttrs(attrs.text, attrs.source)
}

abstract struct rules(
  rules: list<(pattern,string)>
)

private struct pattern(
  elem: string,
  name: string,
  classes: list<string>,
  attrselectors: list<expr>,
  weight: int
)

function show( p : pattern ) {
  "~" + p.elem + "#" + p.name + "." +  p.classes.join(".") +
   p.attrselectors.map(fun(e) { "[" + e.expression/show + "]" }).join
}



function makePattern( elem : string = "", name : string = "",
                      classes : list<string> = [],
                      attrselectors : list<expr> = [],
                      weight : int = ~1) {
  val clss = classes.filter( fun(s) { !s.isEmpty })
  // calculate weight according to CSS rules: in order of importance: name, classes, elements
  val w = if (weight >= 0) then weight
           else (100*(if (name.isEmpty) then 0 else 1) + 10*clss.length + (if (elem.isEmpty) then 0 else 1))
  Pattern(elem.definitionId, name.definitionId, clss, attrselectors, w)
}

public val emptyRules = Rules([])

public function rulesFromMeta( metadata : list<(string,string)> ) : rules {
  val rules = metadata.concat( fun(kv) {
    val (key,value) = kv
    if (key.startsWith("~") || key.startsWith("#") || key.startsWith(".")) {
      match(key.find(rxPattern)) {
        Nothing -> {
          warning("illegal pattern: " + key)
          []
        }
        Just(cap) -> {
          val attrsels = parseAttrSelectors(cap.groups[4])
          val classes  = cap.groups[3].split(".").list
          val pat = makePattern( cap.groups[1], cap.groups[2], classes, attrsels )
          trace("pattern: " + key + " -> " + pat.show )
          [(pat,value)]
        }
      }
    }
    else []
  })
  Rules(rules)
}
val rxPattern = regex(@"^(?:~([\w\-:]+))?(?:#([\w\-:]+))?((?:\.(?:[\w\-:]+))*)(?:(\[[^\]]*\])*)$")

public function matchRules( r : rules, elementName : string, attrs : attrs ) : <console> attrs
{
  // println("\n--- matchRules called attributes ---")
  // println("Element name: " + elementName)
  // println("Attrs: " + attrs.show)
  if (!(attrs.common/defaults)) {
    // println("Skipping rule matching (defaults=false)")
    return attrs
  }
  val name = attrs.name.definitionId
  val elemName = elementName.definitionId
  // println("Looking for rules matching element: " + elemName + ", name: " + name + ", classes: [" + attrs.classes.join(", ") + "]")
  val result = r.rules.apply( attrs, name, elemName, peano10 )
  // println("Final attrs after rule matching: " + result.show)
  result
}

function apply( rules : list<(pattern,string)>, attrs : attrs, name : string, elemName : string, p : peano ) : <console> attrs {
  match(p) {
    Zero -> attrs
    Succ(p1) -> {
      // println("Apply iteration (remaining: " + p1.show + ")")
      val (def,rules2) = rules.getMatches( attrs, name, elemName )
      if (def=="") {
        // println("No matching rules found in this iteration")
        return attrs
      }
      // println("Found matching rule(s), merging attributes with: " + def)
      val attrs2 = attrs.mergeDefault(def.parseAttrs)
      // println("After merging: " + attrs2.show)
      rules2.apply( attrs2, name, elemName, p1 )
    }
  }
}

function getMatches( rules : list<(pattern,string)>, attrs : attrs, name : string, elemName : string ) : <console> (string,list<(pattern,string)>) {
  // println("Checking " + rules.length.show + " rules for matches")
  var def := []
  val newrules = rules.filterx( fun(rule) {
    val (pat,value) = rule
    if (pat.matches(elemName,name,attrs)) {
      // println("MATCHED RULE: weight:" + pat.weight.show + ": " + pat.show + " with value: " + value.substr(0,80))
      def := def.insert(pat.weight, value)
      False
    }
    else {
      True
    }
  })
  val final = def.map(snd).join(" ; ")
  // println("Final merged value: " + final)
  (final,newrules)
}

// insert a pattern value sorted on weight, from low to high
function insert( xs : list<(int,string)>, weight :int, value : string ) : list<(int,string)> {
  match(xs) {
    Nil -> [(weight,value)]
    Cons(wv,xx) -> {
      if (wv.fst <= weight)
       then Cons(wv,insert(xx, weight, value))
       else Cons((weight,value),xs)
    }
  }
}

function matches( pat : pattern, xelem : string, xname : string, attrs : attrs ) : <console> bool {
  val elemMatch = (pat.elem.isEmpty || pat.elem == xelem)
  val nameMatch = (pat.name.isEmpty || pat.name == xname)
  val classesMatch = (pat.classes.isNil || pat.classes.all( fun(c) { attrs.hasClass(c) } ))
  val selectorsMatch = (pat.attrselectors.isNil || pat.attrselectors.all(fun(e) { matchSelector(e,attrs) }))


  // println("  Pattern match check:")
  // println("    - Element match (" + pat.elem + " vs " + xelem + "): " + elemMatch.show)
  // println("    - Name match (" + pat.name + " vs " + xname + "): " + nameMatch.show)
  // println("    - Classes match (" + pat.classes.join(",") + "): " + classesMatch.show)
  // println("    - Attr selectors match: " + selectorsMatch.show)

  elemMatch && nameMatch && classesMatch && selectorsMatch
}

function matchSelector( e : expr, attrs : attrs ) : bool {
  function lookup(v,display) {
    String(expandKeyPattern(v,attrs))
  }
  catch {
    evalExpr(e,lookup).bool
  }
  fun(exn) {
    warning(exn.show)
    False
  }
}

function filterx( xs : list<a>, pred : a -> e bool ) : e list<a>
{
  match(xs) {
    Nil -> Nil
    Cons(x,xx) -> if (pred(x)) then Cons(x,xx.filterx(pred)) else xx.filterx(pred)
  }
}

public function extendAttrs( attrs0 : attrs, attrsStr : string, source : string ) : attrs
{
  if (attrsStr=="" && source=="") then return attrs0
  val attrsx = attrs0(empty=False, sticky=False, source=source,
                      text=attrs0.text + " ; " + attrsStr,
                      classes=[])

  val kvs = attrsStr.joinLines.parseAttributes  // join lines here.

  val attrs = kvs.foldl(attrsx) fun(acc:attrs,kv:(string,string,string)) {
    val (name,kwvalue,value) = kv
    val start = name.substr(0,1)
    if (kwvalue=="clear") {
      if (start==".") {
        val cname = name.substr(1)
        acc(classes = acc.classes.filter(fun(c) { c != cname }))
      }
      elif (start=="@") {
        val cname = name.substr(1)
        acc(counters = acc.counters.filter(fun(c) { c.fst != cname }))
      }
      elif (name=="class") {
        acc(classes = [])
      }
      elif (name=="counters") {
        acc(counters = [])
      }
      elif (name=="replace" || name=="before" || name=="after") {
        acc(replacers = [])
      }
      else {
        acc(keyvals = acc.keyvals.filter( fun(k) { k.fst != name }))
      }
    }
    elif (name=="clear") {
      Attrs(text=attrsx.text,defaults=False)
    }
    elif (name=="-" || name=="clearnum" || name==".clearnum") {
      acc( counters=[], label="", replacers=[],
           classes=["clearnum"] + acc.classes.filter(fun(nm) { nm != "clearnum" }) )
    }
    elif (start=="#") {
      trace("attrs name: " + name + ": " + value.show)
      acc(name = name.substr(1).definitionId, label = if (value!="") then value else acc.label)
    }
    elif (start==".") {
      val cname = name.substr(1)
      if (acc.classes.any( fun(nm) { nm == cname } ))
       then acc else acc(classes = acc.classes + [cname])
    }
    elif (start=="@") {
      trace("counter: " + name + ": " + value)
      acc(counters = acc.counters + [(name.substr(1), value)] )
    }
    elif (name=="elem") {
      val ename = value.definitionId
      acc(elem = ename, classes = [ename] + acc.classes.filter(fun(nm) { nm != ename }) )
    }
    elif (name=="tex-elem") {
      acc(texelem = value )
    }
    elif (name=="html-elem") {
      acc(htmlelem = value )
    }
    elif (name=="id") {
      trace("id: " + value)
      acc(name = value.definitionId )
    }
    elif (name=="class") {
      val cname = value.definitionId
      if (acc.classes.any( fun(nm) { nm == cname } ))
       then acc else acc( classes = acc.classes + [cname] )
    }
    elif (name=="label") {
      acc(label = value)
    }
    elif (name=="sticky") {
      acc(sticky=value.toBool)
    }
    elif (name=="notag") {
      acc(notag=value.toBool)
    }
    elif (name=="tag") {
      acc(notag= !value.toBool)
    }
    elif (name=="line") {
      match(value.parseInt()) {
        Nothing -> {
          warning("unrecognized line number: line=" + value )
          acc
        }
        Just(n) -> acc(lineNo=n)
      }
    }
    elif (name=="replace") {
      acc(replacers = acc.replacers + [value])
    }
    elif (name=="before") {
      acc(replacers = acc.replacers + [value + @"\/&source;"])
    }
    elif (name=="after") {
      acc(replacers = acc.replacers + [@"\/&source;" + value])
    }
    elif (name=="input") {
      val v = kwvalue
      val r = if (v=="pre") then Pre
              elif (v=="raw") then Raw(Nothing)
              elif (v=="texraw") then Raw(Just(FmtTex))
              elif (v=="htmlraw") then Raw(Just(FmtHtml))
              elif (v=="tex") then Tex
              elif (v=="math") then Math
              elif (v=="mathpre") then MathPre
              elif (v=="mathdefs") then MathDefs
              elif (v=="mathpoly") then MathPoly
              elif (v=="normal") then Markdown()
              elif (v=="markdown") then Markdown()
              elif (v=="htmlonly") then Markdown(Just(FmtHtml))
              elif (v=="texonly") then Markdown(Just(FmtTex))
              else {
                warning( "unrecognized input value: " + value)
                Markdown()
              }
      acc(input=r)
    }
    elif (name=="tight") {
      acc(tight=value.toBool)
    }
    else {
      trace("key " + name + "=" + value)
      val cntrs = if (name=="start") then match (value.trim.parseInt) {
                    Just(i) -> acc.counters + [(acc.elem + "-li",(i-1).show)]
                    Nothing -> acc.counters
                  }
                  elif (name=="list-style-type" && acc.elem.bool) then {
                    trace("list-style-type: @" + acc.elem + "-li=" + value.trim )
                    acc.counters + [(acc.elem + "-li",value.trim)]
                  }
                  else acc.counters
      val extra = [parsePageAlign(name,kwvalue)].concat
      acc(keyvals = acc.keyvals.filter(fun(kval) { kval.fst != name && extra.all( fun(kvx) { kvx.fst != kval.fst })}) + [(name,value)] + extra, counters = cntrs)
    }
  }
  attrs.addClasses(attrs0.classes) // last, so the classes are order for 'elementName'
}

val rxId      = @"(?:[\.#][\w\.#@\-:]*|[@\-\w][\w\.#@\-]*)"
val rxQuoted  = @"(?:'(?:[^\n\\']|\\[\s\S])*'|""(?:[^\n\\""]|\\[\s\S])*"")"
val rxHtmlValue = @"(?:" + rxQuoted + "|" + @"(?:[^\\""'\s]|\\.)*)"
val rxCssValue  = @"(?:" + rxQuoted + "|" + @"(?:&(?:#[xX]?)?[\w\-]+;|[^\\""'\s;,]|\\.)*)"
val rxHtmlVal = @"(?:\s*=\s*(" + rxHtmlValue + @"))"
val rxCssVal  = @"(?:\s*:\s*(" + rxCssValue + @"(?:(?:\s+|\s*(,\s*)+)" + rxCssValue + @")*))"
val rxAttr    = regex(@"^(" + rxId + @")(?:" + rxHtmlVal + "|" + rxCssVal + ")?")
val rxSep     = regex(@"^(\s+(?:;*(?:$|\s+))?|;(?:$|\s+))")
val rxNoSep   = regex(@"^([^\s;]|;(?!\s))+")

val rxSpaces  = regex(@"\s+")
val rxNoSpaces= regex(@"\\.|" + rxQuoted)

function parsePageAlign( name :string, value: string ) : list<(string,string)> {
  if (name!="page-align") return []
  val placement = if (value=="top") then "t"
                  elif (value=="bottom") then "b"
                  elif (value=="topbottom") then "tb"
                  elif (value=="page") then "p"
                  elif (value=="here") then "h"
                  elif (value=="forcehere") then "h!"
                  elif (value=="inplace") then "H"
                  else ""
  [("tex-float-placement",placement)]
}


// Parse an attribute string
val parseAttributes : (string) -> list<(string,string,string)> = smemo(parseAttributesX)

function parseAttributesX( s : string ) : list<(string,string,string)>
{
  val res = parseAttributesAcc( s, s, [] )
  res
}

function parseAttributesAcc( original : string, s : string, acc : list<(string,string,string)> ) : list<(string,string,string)>
{
  if (s=="") return acc.reverse
  match(s.find(rxAttr)) {
    Nothing -> match(s.find(rxSep)) {
      Nothing -> match(s.find(rxNoSep)) {
        Nothing -> {
          warning("invalid attribute: " + s + "\n  in: " + original )
          acc.reverse
        }
        Just(cap) -> {
          warning("invalid attribute: " + cap.matched + "\n  in: " + original )
          parseAttributesAcc( original, s.substr1(cap.next), acc )
        }
      }
      Just(cap) -> {
        parseAttributesAcc( original, s.substr1(cap.next), acc )
      }
    }
    Just(cap) -> {
      val values  = cap.groups.firstMatched(2).trim.splitExclude(rxSpaces,rxNoSpaces)
      val value   = values.filter(legalValue).map(unquote).join(" ") // TODO: we should not unquote here but only as needed!
      val kwvalue = if (values.length==1 && !(value.startsWith("\"") || value.startsWith("'")))
                     then value else ""
      val res     = (cap.groups[1].toLower,kwvalue,value)
      parseAttributesAcc( original, s.substr1(cap.next), Cons(res,acc))
    }
  }
}

function legalValue( s : string ) : bool {
  !s.isEmpty && !s.contains(rxCommentValue)
}
val rxCommentValue = regex(@"^/\*(?:[^\\\*]|\\.|\*(?!/))*\*/")

function unescape( s : string ) : string {
  s
}

function toBool( s : string ) : bool {
  (s=="" || s=="true")
}

public function transformText( attrs : attrs, txt : string, labels : dict<label>, metadata : dict<string> ) : string
{
  if (attrs.empty) then return txt
  attrs.replacers.foldl(txt,fun(cur,repl) {
    val res = repl.applyReplacer(cur,attrs,labels,metadata)
    trace("replacer '" + repl.substr(0,10) + "': " + cur + " -> " + res)
    res
  })
}

function applyReplacer( repl : string, txt : string, attrs : attrs, labels : dict<label>, metadata : dict<string> ) : string
{
  function expand( s : string ) {
    expandKeys(peanoN,s,txt,attrs,labels,metadata,fun(_,_) {""})
  }

  function checkReplace( rrepl : string ) : string {
    match(rrepl.find(rxregex)) {
      Nothing -> match(rrepl.find(rxmapping)) {
        Nothing -> rrepl.expand
        Just(mcap) -> {
          regexMapping( mcap.groups[1].expand, mcap.groups[2], txt )
        }
      }
      Just(rcap) -> {
        regexReplacer( rcap.groups[1].expand, rcap.groups[2].expand, rcap.groups[3], txt )
      }
    }
  }

  function checkCond( crepl : string ) : string {
    if (!crepl.startsWith("@if"))
      then checkReplace(crepl)
      else match (evalCondition(crepl,txt,attrs,labels,metadata)) {
        Null -> txt // missing 'else' -> no replace
        c    -> checkReplace(c.string)
      }
  }

  checkCond(repl)
}

val rxmapping = regex(@"^//((?:[^\\]|\\.)*)//([gimc]*)$")


val rxregex = regex(@"^/(" + rxescaped + @"*)/(" + rxescaped + @"*)/([gimc]*)$")
val rxescaped = @"(?:[^\\/]|\\.)"

function evalCondition( cond : string, source : string, attrs : attrs, labels : dict<label>, metadata : dict<string> ) : constant {
  function lookup(v,display) {
    String(expandKeys("&" + v + ";", source,attrs,labels,metadata))
  }
  val res = evaluate( cond, fun(e) { evalExpr(e,lookup) }, String(""))
  trace("eval condition: " + res.show + ": " + cond)
  res
}

// remove all grouping from a regular expression
function ungroup( r : string ) : string {
  r.replaceAll(rxOpenParen, fun(cap) {
    if (cap.groups[1]!="") then "(?:" else cap.matched
    })
}
val rxOpenParen = regex(@"\\.|(\((?!\?))")

val rxEntry      = regex(@"^((?:[^\\/]|\\.)*)/(.*)$")
val rxBar        = regex(@"//")
val rxExcludeBar = regex(@"[^\\/]|\\.|/(?!/)")

// perform a mapping.
function regexMapping( mapping : string, flags : string, txt : string ) : string
{
  val entries
    = mapping.splitExclude(rxBar,rxExcludeBar).map( fun(entry) {
        match(entry.find(rxEntry)) {
          Just(ecap) -> {
            (ecap.groups[1],ecap.groups[2])
          }
          Nothing -> {
            warning("illegal mapping: " + entry)
            (entry,"")
          }
        }
      })

  val rexp = regex( entries.map(fun(e){"(" + e.fst.ungroup + ")"}).join("|"), ignoreCase=flags.contains("i"), multiline=flags.contains("m"))
  val convCase = flags.contains("c")

  function replaceGroups( cap : matched ) {
    val i = cap.groups.firstMatchedOn(1,entries.length)
    if (i<=0) return ""
    val subst = match(entries.drop(i-1)) {
      Nil -> cap.matched // should never happen
      Cons(entry) -> {
        val (rx,repl) = entry
        match(cap.matched.find(regex(rx))) // should always match from start to end...
        {
          Nothing -> cap.matched // should never happen
          Just(rcap) -> {
            // assert: cap.matched == rcap.matched
            repl.replaceAll(rxCaptureGroup, fun(gcap) {
              if (gcap.groups[1] != "\\") {
                val j = gcap.groups[1].parseInt.maybe(0,id)
                if (convCase)
                 then rcap.groups[j].replaceAll(rxCaseEsc,@"\\$2$1") // escape replacement
                 else rcap.groups[j]
              }
              else {
                gcap.groups[1]
              }
            })
          }
        }
      }
    }
    if (convCase)
     then subst.caseConvert // unescape replacement
     else subst
  }

  val gtxt = if (flags.contains("g"))
              then txt.replaceAll(rexp,replaceGroups)
              else txt.replace(rexp,replaceGroups)
  gtxt
}

// "?#caption?/././"
// val rxcond  = regex(@"^/[?](" + rxescaped + @"+)/(" + rxescaped + @"*)/([gim]*)$")

function regexReplacer( rxText : string, rtxt : string, flags : string, txt : string )
{
  val rexp = regex(rxText, ignoreCase=flags.contains("i"), multiline=flags.contains("m"))
  val convCase = flags.contains("c")

  function replaceGroups( cap : matched ) {
    val repl = rtxt.replaceAll( rxCaptureGroup, fun(gcap) {
      if (gcap.groups[1] != "\\") {
        val i = gcap.groups[1].parseInt.maybe(0,id)
        if (convCase)
         then cap.groups[i].replaceAll( rxCaseEsc, @"\\$2$1" ) // escape replacement
         else cap.groups[i]
      }
      else {
        gcap.groups[1]
      }
    })
    if (convCase)
     then repl.caseConvert  // do case conversion (and unescape replacements)
     else repl
  }
  val gtxt = if (flags.contains("g"))
              then txt.replaceAll(rexp,replaceGroups)
              else txt.replace(rexp,replaceGroups)
  trace("replace (" + rxText.substr(0,20) + "): '" + txt + "' to '" + gtxt + "'")
  gtxt
}

val rxCaptureGroup = regex(@"\\([\d\\])")
val rxCaseEsc = regex(@"\\((\\)|[/ulULE])")
//val rxRegEsc  = regex(@"\\((\\)|[/])")

function caseConvert( txt : string ) : string {
  txt.replaceAll(regex(@"\\([\\/E])|\\([ul])(.)|\\([UL])([\s\S]*?)(\\E|$)"), fun(cap) {
    if (cap.groups.matchedOn(1)) {
      cap.groups[1] // unescape
    }
    elif (cap.groups.matchedOn(2)) {
      if (cap.groups[2]=="u") then cap.groups[3].toUpper else cap.groups[3].toLower
    }
    elif (cap.groups.matchedOn(4)) {
      if (cap.groups[4]=="U") then cap.groups[5].toUpper else cap.groups[5].toLower
    }
    else cap.matched
  })
}


public function expand( attrs : attrs, metadata : dict<string>, labels : dict<label> = dict() ) : attrs {
  if (attrs.empty) return attrs

  attrs( keyvals = attrs.keyvals.map fun(kv) {
    (kv.fst, kv.snd.expandKeys( attrs.source, attrs, labels, metadata ))
  })
}

public function expandKeys( txt : string, metadata : dict<string> ) : string {
  expandKeys(peanoN,txt,"",attrsNone,dict(),metadata)
}

public function expandKeyName( name : string, labels : dict<label>, metadata : dict<string> ) : string {
  expandKeys(peanoN,"&" + name + ";","",attrsNone,labels,metadata)
}

public function expandKeys( txt : string, source : string,
                            attrs : attrs,
                            labels : dict<label>, metadata : dict<string> ) : string {
  expandKeys(peanoN,txt,source,attrs,labels,metadata)
}

function expandKeyPattern( name : string, attrs : attrs ) : string {
  expandKeys(peanoN,"&" + name + ";",attrs.source,attrs,dict(), dict(), ignoreNotFound)
}

// expand keys in a string
private function expandKeys( p0 : peano, txt : string, source : string,
                            attrs : attrs,
                            labels : dict<label>, metadata : dict<string>,
                            notFound : (string,string) -> string = keyNotFound ) : string
{
  if (txt=="") then return txt
  match(p0) {
    Zero -> txt
    Succ(p) -> {
      txt.replaceAll(rxkey) fun(cap) {
        val rawkey = cap.groups[1]
        val key = rawkey.normalizeId
        if (rawkey=="") then cap.matched  // no key was matched
        elif (rawkey=="&") then "&"       // special in replacements
        elif (key=="label" && !(attrs.empty)) then attrs.label
        elif (key=="id" && !(attrs.empty)) then attrs.name
        elif (key=="class" && !(attrs.empty)) then attrs.classes.join(" ")
        elif (key=="source" && !(attrs.empty)) then source // attrs.source
        else match (attrs.keyvals.find(fun(kv){ kv.fst == key })) {
          Just(kv) -> {
            if (txt == kv.snd) then kv.snd
             else expandKeys(p,kv.snd,source,attrs,dict(),metadata,notFound)
          }
          Nothing  -> match(labels[key]) {
            Just(label) -> label.labelText // already expanded
            Nothing -> match(metadata[key]) {
              Just(value) -> {
                // semi-static scoping: clear out labels, but keep attributes
                expandKeys(p,value,source,attrs,dict(),metadata,notFound)
                // todo? full static scoping: clear out attributes and labels..
                //expandKeys(p,value,"",attrsNone,dict(),metadata,notFound)
              }
              Nothing -> match(entityNameAsNum(rawkey)) {
                Just(value) -> value
                Nothing     -> notFound(key,cap.matched)
                //entityNameToNum(key)
              }
            }
          }
        }
      }
    }
  }
}
val rxkey = regex(@"\\&|(?:\\/)?&([\w\-:]*|&);(\\/)?")

function keyNotFound( key: string, matched : string ) : string {
  warning( "undefined key: " + key)
  matched
}

function ignoreNotFound( key: string, matched : string ) : string {
  matched
}


external smemo( f : (string) -> e a ) : (string -> e a) {
  js inline "((function(){ var dict={}; return (function(s) { if (dict[s]===undefined) dict[s] = (#1)(s); return dict[s]; }); })())"
}
