%class LingoModule;
%fallback ID IF VAR;

%walkers Walker;
%walker_traversal Walker manual;

%members Walker %{
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
        std::print("importing {} as {}\n", f.text, n);
        std::ifstream is(f.text);
        if(!is) {
            throw Error(f.pos.row, f.pos.col, f.pos.file, "cannot open file:{}", f.text);
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

stmts := stmts(sl) stmt(s)
%{
    go(sl);
    go(s);
%}

stmts := stmt(s)
%{
    go(s);
%}

stmt := IMPORT STRING(F) AS ID(N) SEMI
%{
    addImport(F, N.text);
%}

stmt := IMPORT STRING(F) SEMI
%{
    auto n = std::filesystem::path(F.text).stem();
    addImport(F, n.string());
%}

stmt := argsx(out) ID(NAME) argsx(in) stmt_block(body)
%{
    fns[NAME.text] = std::make_unique<FunctionDecl>(NAME);
    auto& fn = *(fns[NAME.text]);
    fn.in = go(in);
    fn.out = go(out);
    fn.body = &(body.node);
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

stmt_block := LCURLY stmts(s) RCURLY
%{
    StatementBlockGuard bg(blocks);
    go(s);
%}

stmt_block := LCURLY RCURLY;

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

stmt := IF LBRACKET l_expr(ne) RBRACKET stmt_block(tsb)
%{
    auto e = go(ne);
    if(boolValue(e) == true) {
        go(tsb);
    }
%}

stmt := IF LBRACKET l_expr(ne) RBRACKET stmt_block(tsb) ELSE stmt_block(fsb)
%{
    auto e = go(ne);
    if(boolValue(e) == true) {
        go(tsb);
    } else {
        go(fsb);
    }
%}

stmt := WHILE LBRACKET l_expr(ne) RBRACKET LCURLY stmts(tsb) RCURLY
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
expr := l_expr(nl)
%{
    auto l = go(nl);
    return l;
%}

%function l_expr -> DataType;
l_expr := l_expr(nl) AND l_expr(nr)
%{
    auto l = go(nl);
    if(boolValue(l) == false) {
        return false;
    }
    auto r = go(nr);
    return boolValue(r);
%}

l_expr := l_expr(nl) OR l_expr(nr)
%{
    auto l = go(nl);
    if(boolValue(l) == true) {
        return true;
    }
    auto r = go(nr);
    return boolValue(r);
%}

l_expr := NOT l_expr(nl)
%{
    auto l = go(nl);
    return (boolValue(l) == false);
%}

l_expr := c_expr(nl)
%{
    auto l = go(nl);
    return l;
%}

%function c_expr -> DataType;
c_expr := c_expr(nl) EQ c_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) == 0;
%}

c_expr := c_expr(nl) NEQ c_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) != 0;
%}

c_expr := c_expr(nl) LTE c_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) <= 0;
%}

c_expr := c_expr(nl) GTE c_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) >= 0;
%}

c_expr := c_expr(nl) LT c_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) < 0;
%}

c_expr := c_expr(nl) GT c_expr(nr)
%{
    auto l = go(nl);
    auto r = go(nr);
    return compare(l, r) > 0;
%}

c_expr := a_expr(nl)
%{
    auto l = go(nl);
    return l;
%}

%function a_expr -> DataType;
a_expr := a_expr(nl) PERCENT a_expr(nr)
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

a_expr := a_expr(nl) STAR a_expr(nr)
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

a_expr := a_expr(nl) FSLASH a_expr(nr)
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

a_expr := a_expr(nl) PLUS a_expr(nr)
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

a_expr := a_expr(nl) MINUS a_expr(nr)
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

a_expr := PRINT LBRACKET STRING(S) COMMA tuple(np) RBRACKET
%{
    auto p = go(np);
    std::print("{}", fmt(S, p));
    return 0;
%}

a_expr := PRINT LBRACKET STRING(S) COMMA a_expr(np) RBRACKET
%{
    auto p = go(np);
    if(auto v = p.ptr<Tuple>()) {
        std::print("{}", fmt(S, *v));
    }else{
        std::print("{}:<not a tuple>", S.text);
    }
    return 0;
%}

a_expr := PRINT LBRACKET STRING(S) RBRACKET
%{
    std::print("{}", fmt(S, {}));
    return 0;
%}

a_expr := NUM(N)
%{
    auto v = std::atoi(N.text.c_str());
    return v;
%}

a_expr := STRING(S)
%{
    return S.text;
%}

a_expr := ID(I)
%{
    return getVar(I);
%}

a_expr := ID(I) xtuple(np)
%{
    auto p = go(np);
    auto& fd = getFunc(I);
    assert(fd.body);
    if(p.size() != fd.in.size()) {
        throw Error(I.pos.row, I.pos.col, I.pos.file, "parameter count mismatch");
    }

    FunctionBlockGuard in(blocks);
    for(auto& ip : fd.in) {
        auto& ti = p.at(ip.name.text);
        addVar(ip.name, ti.val);
    }

    WalkerNodeRef<stmt_block> body(*(fd.body));
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

IF := "if";
ELSE := "else";
WHILE := "while";
RETURN := "return";

INT_TYPE := "int";
STRING_TYPE := "string";

LBRACKET := "\(";
RBRACKET := "\)";
LCURLY := "\{";
RCURLY := "\}";
SEMI := ";";
COMMA := ",";
VAR := "var";
PRINT := "print";

ID := "[A-Za-z][A-Za-z0-9_]*";
STRING := "(!\")[^\"]*(!\")";
NUM := "[0-9]+";

PERCENT := "%";
STAR := "\*";
FSLASH := "/";
PLUS := "\+";
MINUS := "-";

ASSIGN := "=";

EQ := "==";
NEQ := "!=";
LTE := "<=";
GTE := ">=";
LT := "<";
GT := ">";

AND := "&&";
OR := "\|\|";
NOT := "!";

SLCOMMENT := "//.*\n"!;
ENTER_MLCOMMENT := "/\*"! [ML_COMMENT_MODE];
WS := "\s"!;

%lexer_mode ML_COMMENT_MODE;
ENTER_MLCOMMENT := "/\*"! [ML_COMMENT_MODE];
LEAVE_MLCOMMENT := "\*/"! [^];
CMT := ".*"!;
