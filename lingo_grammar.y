%class LingoModule;

%walkers Interpreter;

%members Interpreter %{
    using Token = LingoModule_AST::Token;
    using Error = LingoModule::Error;
    struct TupleItem;
    struct DataType;

    struct Tuple {
        using TupleT = std::unordered_map<std::string, TupleItem>;
        TupleT val;

        inline Tuple() {}
        inline Tuple(const Tuple& src) : val(src.val) {}
        inline Tuple(Tuple&& src) : val(std::move(src.val)) {}
        inline Tuple& operator=(const Tuple& src) {val = src.val;return *this;}
        inline Tuple& operator=(Tuple&& src)  {val = std::move(src.val);return *this;}

        inline const DataType* get(const std::string& name) const {
            if(auto it = val.find(name); it != val.end()) {
                return &(it->second.val);
            }
            return nullptr;
        }

        inline void set(const std::string& name, const TupleItem& ti){
            if(auto it = val.find(name); it != val.end()) {
                val.erase(it);
            }
            val.insert(std::make_pair(name, ti));
        }

        inline size_t size() const {
            return val.size();
        }

        inline const TupleItem& at(const std::string& name) const {
            auto dt = get(name);
            if(dt == nullptr) {
                throw std::runtime_error("setReturn: no var found:" + name);
            }
            return val.at(name);
        }
    };

    struct DataType {
        using DataTypeT = std::variant<bool, int64_t, std::string, Tuple>;
        DataTypeT val;

        inline DataType() : val(false) {}
        inline DataType(const bool& v) : val(v) {}
        inline DataType(const int& v) : val(static_cast<int64_t>(v)) {}
        inline DataType(const int64_t& v) : val(v) {}
        inline DataType(const std::string& v) : val(v) {}
        inline DataType(const Tuple& v) : val(v) {}

        template<typename T>
        inline const T* ptr() const {
            if(auto pr = std::get_if<T>(&val)) {
                return pr;
            }
            return nullptr;
        }

        template<typename T>
        [[maybe_unused]] // TODO: Why?
        inline const T& get() const {
            return std::get<T>(val);
        }
    };

    struct TupleItem {
        Token name;
        DataType val;

        inline TupleItem(const Token& n, const DataType& v) : name(n), val(std::move(v)) {}
        inline TupleItem(const TupleItem& src) : name(src.name), val(src.val) {}
        inline TupleItem& operator=(const TupleItem& src) {
            name = src.name;
            val = src.val;
            return *this;
        }

        inline TupleItem(TupleItem&&) = delete;
        inline TupleItem operator=(TupleItem&&) = delete;
    };

    struct StatementBlock {
        enum class Type {
            Function,
            Statement,
        };
        Type type = Type::Statement;
        Tuple vars;
        Tuple ret;
        bool returned = false;
    };

    template<typename SBT, SBT T>
    struct BlockGuard {
        std::vector<std::unique_ptr<StatementBlock>>& blocks;

        inline BlockGuard(std::vector<std::unique_ptr<StatementBlock>>& bs) : blocks(bs) {
            blocks.push_back(std::make_unique<StatementBlock>());
            auto& b = *(blocks.back());
            b.type = T;
        }

        inline ~BlockGuard() {
            blocks.pop_back();
        }
    };

    using FunctionBlockGuard = BlockGuard<StatementBlock::Type, StatementBlock::Type::Function>;
    using StatementBlockGuard = BlockGuard<StatementBlock::Type, StatementBlock::Type::Statement>;

    struct ArgDef {
        const Token type;
        const Token name;
        inline ArgDef(const Token& t, const Token& n) : type(t), name(n) {}
    };

    struct FunctionDecl {
        const Token& name;
        std::vector<ArgDef> in;
        std::vector<ArgDef> out;
        const stmt_block* body = nullptr;
        inline FunctionDecl(const Token& n) : name(n) {}
    };

    std::unordered_map<std::string, std::unique_ptr<TAG(CLASSQID)>> mods;
    std::vector<std::unique_ptr<StatementBlock>> blocks;
    std::unordered_map<std::string, std::unique_ptr<FunctionDecl>> fns;

    inline std::string str(const DataType& dt) {
        struct Visitor {
            inline std::string operator()(const bool& v) const {
                return std::format("{}", v);
            }
            inline std::string operator()(const int64_t& v) const {
                return std::format("{}", v);
            }
            inline std::string operator()(const std::string& v) const {
                return std::format("{}", v);
            }
            inline std::string operator()(const Tuple& v) const {
                std::ostringstream os;
                std::string sep;
                os << "(";
                for(auto& m : v.val) {
                    os << sep << m.first << "=" << std::visit(Visitor(), m.second.val.val);
                    sep = ",";
                }
                os << ")";
                return os.str();
            }
        };
        return std::visit(Visitor(), dt.val);
    }

    inline std::string fmt(const Token& f, const Tuple& dtl) {
        std::ostringstream os;
        enum class State {
            Text,
            Esc0,
            Fmt0,
            Fmt1,
        };

        State state = State::Text;
        std::string key;
        for(auto& c : f.text) {
            switch(state) {
            case State::Text:
                if(c == '{') {
                    key = "";
                    state = State::Fmt0;
                    break;
                }
                if(c == '\\') {
                    state = State::Esc0;
                    break;
                }
                os << c;
                break;
            case State::Esc0:
                if(c == 'n') {
                    os << "\n";
                }else {
                    os << "\\" << c;
                }
                state = State::Text;
                break;
            case State::Fmt0:
                if(c == '}') {
                    throw Error(f.pos.row, f.pos.col, f.pos.file, "empty format key");
                }
                key += c;
                state = State::Fmt1;
                break;
            case State::Fmt1:
                if(c == '}') {
                    os << str(dtl.at(key).val);
                    state = State::Text;
                    break;
                }
                key += c;
                break;
            }
        }
        return os.str();
    }

    inline void addImport(const Token& f, const std::string& n) {
        auto pdir = std::filesystem::path(f.pos.file).parent_path();
        auto fpath = pdir / f.text;
        fpath = std::filesystem::canonical(fpath);
        
        std::println("importing {} as {}", fpath.string(), n);
        std::ifstream is(fpath);
        if(!is) {
            throw Error(f.pos.row, f.pos.col, f.pos.file, "cannot open file:{}", fpath.string());
        }

        auto m = std::make_unique<TAG(CLASSQID)>(n);
        m->beginStream();
        m->readStream(is, f.text);
        m->endStream();
        mods[n] = std::move(m);
    }

    inline const FunctionDecl& getFunc(const Token& name) {
        if(auto it = fns.find(name.text); it != fns.end()) {
            FunctionDecl& fd = *(it->second);
            return fd;
        }
        throw Error(name.pos.row, name.pos.col, name.pos.file, "undefined function:{}", name.text);
    }

    inline const DataType* _getVar(const std::string& name) {
        assert(blocks.size() > 0);
        for(auto& b : blocks | std::views::reverse ) {
            if(auto dt = b->vars.get(name)) {
                return dt;
            }
        }
        return nullptr;
    }

    inline const DataType& getVar(const Token& name) {
        auto dt = _getVar(name.text);
        if(dt == nullptr) {
            throw Error(name.pos.row, name.pos.col, name.pos.file, "undefined variable:{}", name.text);
        }
        return *dt;
    }

    inline const DataType* hasVar(const Token& name) {
        auto dt = _getVar(name.text);
        return dt;
    }

    inline void addVar(const Token& name, const TupleItem& ti) {
        if(_getVar(name.text) != nullptr) {
            throw Error(name.pos.row, name.pos.col, name.pos.file, "variable already defined:{}", name.text);
        }
        auto& block = *(blocks.back());
        block.vars.set(name.text, ti);
    }

    inline void addVar(const Token& name, const DataType& dt) {
        addVar(name, TupleItem(name, dt));
    }

    inline void setVar(const Token& name, const DataType& dt) {
        assert(blocks.size() > 0);
        for(auto& b : blocks | std::views::reverse ) {
            if(b->vars.get(name.text) != nullptr) {
                b->vars.set(name.text, TupleItem(name, dt));
                return;
            }
        }
        throw Error(name.pos.row, name.pos.col, name.pos.file, "undefined variable:{}", name.text);
    }

    inline const bool& returned() {
        assert(blocks.size() > 0);
        for(auto& b : blocks | std::views::reverse ) {
            if(b->type == StatementBlock::Type::Function) {
                return b->returned;
            }
        }
        throw std::runtime_error("returned: no function block found");
    }

    inline const Tuple& getReturn() {
        assert(blocks.size() > 0);
        for(auto& b : blocks | std::views::reverse ) {
            if(b->type == StatementBlock::Type::Function) {
                return b->ret;
            }
        }
        throw std::runtime_error("getReturn: no function block found");
    }

    inline void setReturn(Tuple& val) {
        assert(blocks.size() > 0);
        for(auto& b : blocks | std::views::reverse ) {
            if(b->type == StatementBlock::Type::Function) {
                b->ret = std::move(val);
                b->returned = true;
                return;
            }
        }
        throw std::runtime_error("setReturn: no function block found");
    }

    inline bool boolValue(const DataType& d) {
        if(auto pr = d.ptr<bool>()) {
            return *pr;
        }
        if(auto pr = d.ptr<int64_t>()) {
            return (*pr != 0);
        }
        if(auto pr = d.ptr<std::string>()) {
            return (pr->size() > 0);
        }
        return false;
    }

    inline int compare(const DataType& lhs, const DataType& rhs) {
        if(auto pl = lhs.ptr<bool>()) {
            if(auto pr = rhs.ptr<bool>()) {
                if(*pl < *pr) {
                    return -1;
                }
                if(*pl > *pr) {
                    return 1;
                }
                return 0;
            }
        }
        if(auto pl = lhs.ptr<int64_t>()) {
            if(auto pr = rhs.ptr<int64_t>()) {
                if(*pl < *pr) {
                    return -1;
                }
                if(*pl > *pr) {
                    return 1;
                }
                return 0;
            }
        }
        if(auto pl = lhs.ptr<std::string>()) {
            if(auto pr = rhs.ptr<std::string>()) {
                if(*pl < *pr) {
                    return -1;
                }
                if(*pl > *pr) {
                    return 1;
                }
                return 0;
            }
        }
        throw std::runtime_error("type mismatch");
    }
%}

start := stmts(s)
%{
    StatementBlockGuard bg(blocks);
    go(s);
%}

stmts := stmts stmt;
stmts := stmt;
stmts := ;

stmt_block := LCURLY stmts(s) RCURLY
%{
    StatementBlockGuard bg(blocks);
    go(s);
%}

stmt_block := LCURLY RCURLY;

stmt := IMPORT string_primitive(sp) AS ID(N) SEMI
%{
    auto s = go(sp);
    addImport(s, N.text);
%}

stmt := IMPORT string_primitive(sp) SEMI
%{
    auto s = go(sp);
    auto n = std::filesystem::path(s.text).stem();
    addImport(s, n.string());
%}

stmt := argsx(out) ID(NAME) argsx(in) stmt_block(body)
%{
    fns[NAME.text] = std::make_unique<FunctionDecl>(NAME);
    auto& fn = *(fns[NAME.text]);
    fn.in = go(in);
    fn.out = go(out);
    fn.body = &(body.node);
    skip(body);
%}

%function argsx -> std::vector<ArgDef>;
argsx := LBRACKET ^args(l) RBRACKET
%{
    return go(l);
%}

argsx := LBRACKET RBRACKET
%{
    auto l = std::vector<ArgDef>();
    return l;
%}

%function args -> std::vector<ArgDef>;
args := args(nl) COMMA arg(na)
%{
    auto l = go(nl);
    auto a = go(na);
    l.push_back(a);
    return l;
%}

args := arg(na)
%{
    auto a = go(na);
    auto l = std::vector<ArgDef>();
    l.push_back(a);
    return l;
%}

%function arg -> ArgDef;
arg := type(nt) ID(I)
%{
    auto t = go(nt);
    return ArgDef(t, I);
%}


stmt := expr(e) SEMI
%{
    go(e);
%}

stmt := RETURN xtuple(t) SEMI
%{
    auto r = go(t);
    setReturn(r);
%}

stmt := VAR ID(V) ASSIGN expr(ne) SEMI
%{
    auto e = go(ne);
    addVar(V, e);
%}

stmt := ID(V) ASSIGN expr(ne) SEMI
%{
    auto e = go(ne);
    setVar(V, e);
%}

stmt := IF LBRACKET logical_expr(ne) RBRACKET stmt_block(tsb)
%{
    auto e = go(ne);
    if(boolValue(e) == true) {
        go(tsb);
    }
%}

stmt := IF LBRACKET logical_expr(ne) RBRACKET stmt_block(tsb) ELSE stmt_block(fsb)
%{
    auto e = go(ne);
    if(boolValue(e) == true) {
        go(tsb);
    } else {
        go(fsb);
    }
%}

stmt := WHILE LBRACKET logical_expr(ne) RBRACKET LCURLY stmts(tsb) RCURLY
%{
    while(true) {
        auto e = go(ne);
        if(boolValue(e) == false) {
//            std::print("breaking\n");
            break;
        }
        go(tsb);
    }
%}

%function expr -> DataType;
expr := logical_expr(e)
%{
    auto v = go(e);
    return v;
%}

%function logical_expr -> DataType;
logical_expr := logical_expr(nl) AND logical_expr(nr)
%{
    auto l = go(nl);
    if(boolValue(l) == false) {
        return false;
    }
    auto r = go(nr);
    return boolValue(r);
%}

logical_expr := logical_expr(nl) OR logical_expr(nr)
%{
    auto l = go(nl);
    if(boolValue(l) == true) {
        return true;
    }
    auto r = go(nr);
    return boolValue(r);
%}

logical_expr := NOT logical_expr(nl)
%{
    auto l = go(nl);
    return (boolValue(l) == false);
%}

logical_expr := conditional_expr(nl)
%{
    auto l = go(nl);
    return l;
%}

%function conditional_expr -> DataType;
conditional_expr := conditional_expr(nl) EQ add_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) == 0;
%}

conditional_expr := conditional_expr(nl) NEQ add_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) != 0;
%}

conditional_expr := conditional_expr(nl) LTE add_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) <= 0;
%}

conditional_expr := conditional_expr(nl) GTE add_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) >= 0;
%}

conditional_expr := conditional_expr(nl) LT add_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) < 0;
%}

conditional_expr := conditional_expr(nl) GT add_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) > 0;
%}

conditional_expr := add_expr(nl)
%{
    auto l = go(nl);
    return l;
%}

%function add_expr -> DataType;
add_expr := add_expr(nl) PLUS multiply_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    if(auto pl = l.ptr<int64_t>()) {
        if(auto pr = r.ptr<int64_t>()) {
            return *pl + *pr;
        }
    }
    if(auto pl = l.ptr<std::string>()) {
        if(auto pr = r.ptr<std::string>()) {
            return *pl + *pr;
        }
    }
    throw Error(nl.node.pos.row, nl.node.pos.col, nl.node.pos.file, "invalid operands for + operator");
%}

add_expr := add_expr(nl) MINUS multiply_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    if(auto pl = l.ptr<int64_t>()) {
        if(auto pr = r.ptr<int64_t>()) {
            return *pl - *pr;
        }
    }
    throw Error(nl.node.pos.row, nl.node.pos.col, nl.node.pos.file, "invalid operands for - operator");
%}

add_expr := multiply_expr(e)
%{
    auto v = go(e);
//    std::println("add_expr:{}", v);
    return v;
%}

%function multiply_expr -> DataType;
multiply_expr := multiply_expr(nl) STAR primary_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    if(auto pl = l.ptr<int64_t>()) {
        if(auto pr = r.ptr<int64_t>()) {
            return *pl * *pr;
        }
    }
    throw Error(nl.node.pos.row, nl.node.pos.col, nl.node.pos.file, "invalid operands for * operator");
%}

multiply_expr := multiply_expr(nl) PERCENT primary_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    if(auto pl = l.ptr<int64_t>()) {
        if(auto pr = r.ptr<int64_t>()) {
            return *pl % *pr;
        }
    }
    throw Error(nl.node.pos.row, nl.node.pos.col, nl.node.pos.file, "invalid operands for % operator");
%}

multiply_expr := multiply_expr(nl) FSLASH primary_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    if(auto pl = l.ptr<int64_t>()) {
        if(auto pr = r.ptr<int64_t>()) {
            return *pl / *pr;
        }
    }
    throw Error(nl.node.pos.row, nl.node.pos.col, nl.node.pos.file, "invalid operands for / operator");
%}

multiply_expr := primary_expr(e)
%{
    auto v = go(e);
    return v;
%}

%function primary_expr -> DataType;
primary_expr := LBRACKET expr(e) RBRACKET
%{
    auto v = go(e);
    return v;
%}

primary_expr := qualified_id(qid)
%{
    auto q = go(qid);
    return q;
%}

%function qualified_id -> DataType;
qualified_id := qualified_id(qid) DOT ID(I)
%{
    auto q = go(qid);
    if(auto t = q.ptr<Tuple>()) {
        auto val = t->at(I.text).val;
        return val;
    }
    throw Error(I.pos.row, I.pos.col, I.pos.file, "not a compound type");
%}

qualified_id := ID(I)
%{
    return getVar(I);
%}

primary_expr := NUM(N)
%{
    auto v = std::stoi(N.text);
    return v;
%}

primary_expr := PRINT(P) LBRACKET string_primitive(sp) RBRACKET
%{
    auto s = go(sp);
    if(P.text == "print") {
        std::print("{}", s.text);
    }else{
        std::println("{}", s.text);
    }
    return 0;
%}

primary_expr := string_primitive(s)
%{
    auto str = go(s);
    return str.text;
%}

%function string_primitive -> Token;
string_primitive := string_parts(segments)
%{
    auto str = go(segments);
    return str;
%}

%function string_parts -> Token;
string_parts := string_parts(ns) string_part(sp)
%{
    auto str = go(ns);
    auto s = go(sp);
    str.text += s.text;
    return str;
%}

string_parts := string_part(sp)
%{
    auto s = go(sp);
    return s;
%}

%function string_part -> Token;
string_part := STRING_SEGMENT(S)
%{
    return S;
%}

string_part := ENTER_STRING_ARG expr(e) LEAVE_STRING_ARG
%{
    auto val = go(e);
    Token R;
    R.text = str(val);
    return R;
%}

primary_expr := ID(I) xtuple(np)
%{
    auto p = go(np);
    auto& fd = getFunc(I);
    assert(fd.body);
    if(p.size() != fd.in.size()) {
        throw Error(I.pos.row, I.pos.col, I.pos.file, "parameter count mismatch");
    }

    std::println("fn-call:{}", I.text);
    FunctionBlockGuard in(blocks);
    for(auto& ip : fd.in) {
        auto& ti = p.at(ip.name.text);
        std::println("arg {}={}", ip.name.text, str(ti.val));
        addVar(ip.name, ti.val);
    }

    NodeRef<stmt_block> body(*(fd.body));
    go(body);
    return getReturn();
%}

%function xtuple -> Tuple;
xtuple := LBRACKET ^tuple(nl) RBRACKET
%{
    auto l = go(nl);
    return l;
%}

xtuple := LBRACKET RBRACKET
%{
    auto l = Tuple();
    return l;
%}

%function tuple -> Tuple;
tuple := tuple(nl) COMMA tupleItem(nt)
%{
    auto l = go(nl);
    auto t = go(nt);
    l.set(t.name.text, std::move(t));
    return l;
%}

tuple := tupleItem(nt)
%{
    auto t = go(nt);
    auto l = Tuple();
    l.set(t.name.text, std::move(t));
    return l;
%}

%function tupleItem -> TupleItem;
tupleItem := ID(I) ASSIGN expr(ne)
%{
    auto e = go(ne);
    return TupleItem(I, e);
%}

%function vtype -> Token;
vtype := type(nt)
%{
    auto t = go(nt);
    return t;
%}

vtype := VAR(T)
%{
    return T;
%}

%function type -> Token;
type := INT_TYPE(T)
%{
    return T;
%}

type := STRING_TYPE(T)
%{
    return T;
%}

IMPORT := "import";
AS := "as";
VAR := "var";

IF := "if";
ELSE := "else";
WHILE := "while";
RETURN := "return";
PRINT := "print";
PRINT := "println";

INT_TYPE := "int";
STRING_TYPE := "string";

LCURLY := "\{";
RCURLY := "\}";
SEMI := ";";
COMMA := ",";

ASSIGN := "=";
ENTER_STRING := "(!\")"! [STRING_MODE];

%lexer_include EXPR_MODE;

SLCOMMENT := "//.*\n"!;
ENTER_MLCOMMENT := "/\*"! [ML_COMMENT_MODE];

%lexer_mode ML_COMMENT_MODE;
ENTER_MLCOMMENT := "/\*"! [ML_COMMENT_MODE];
LEAVE_MLCOMMENT := "\*/"! [^];
CMT := ".*"!;

%lexer_mode STRING_MODE;
LEAVE_STRING := "(!\")"! [^];
STRING_SEGMENT := "[^\"\{]+";
ENTER_STRING_ARG := "\{" [STRING_ARG_MODE];

%lexer_mode STRING_ARG_MODE;
LEAVE_STRING_ARG := "\}" [^];
%lexer_include EXPR_MODE;

%lexer_mode EXPR_MODE;
ID := "[a-zA-Z_][a-zA-Z0-9_]*";

LBRACKET := "\(";
RBRACKET := "\)";
DOT := "\.";

AND := "&&";
OR := "\|\|";
NOT := "!";

EQ := "==";
NEQ := "!=";
LTE := "<=";
GTE := ">=";
LT := "<";
GT := ">";

STAR := "\*";
FSLASH := "/";
PERCENT := "%";
PLUS := "\+";
MINUS := "-";

NUM := "[0-9]+";
WS := "\s"!;
