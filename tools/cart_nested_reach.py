import re,sys
tree,sym_name,lst_name=sys.argv[1:4]
B=f'{tree}/build/'
sym={}
for l in open(B+sym_name):
    m=re.match(r'(\S+):\s+EQU\s+0x([0-9A-Fa-f]+)',l)
    if m: sym[m.group(1)]=int(m.group(2),16)
ins={}  # addr -> (text, scope)
scope=''
rx=re.compile(r'^\s*\d+\+*\s+([0-9A-F]{4})\s((?:[0-9A-F]{2} ){0,4})\s*(.*)$')
for l in open(B+lst_name,errors='replace'):
    m=rx.match(l)
    if not m: continue
    a=int(m.group(1),16); by=m.group(2); src=m.group(3).split(';')[0].rstrip()
    lab=re.match(r'^([A-Za-z_.][\w.]*):',src.strip())
    if lab and not lab.group(1).startswith('.'): scope=lab.group(1)
    t=re.sub(r'^[A-Za-z_.][\w.]*:\s*','',src.strip())
    if by and t and a<0x4000 and t.split()[0].lower() in ('call','jp','jr','djnz','ret','rst','reti','retn','ld','push','pop','add','inc','dec','or','and','xor','cp','sub','sbc','adc','ex','exx','ei','di','nop','halt','out','in','rl','rr','sla','sra','srl','rla','rra','rlca','rrca','bit','set','res','ldir','lddr','neg','cpl','scf','ccf','daa','im','ldi','cpir','cpi','outi','otir','rrd','rld','djnz'):
        ins.setdefault(a,(t,scope))
addrs=sorted(ins)
nxt={a:addrs[i+1] for i,a in enumerate(addrs[:-1])}
def resolve(tok,scope):
    tok=tok.strip()
    if tok.startswith('.'): return sym.get(scope+tok)
    if tok in sym: return sym[tok]
    try: return int(tok.replace('$','0x'),0)
    except: return None
targets=[ 'GFX_WRITE_PIXEL','GFX_SET_ATTR','GFX_LINE','GFX_ROW_BASE_ADDR','GFX_CELL_ATTR_ADDR']
goal={sym['EXROM_CALL_SLOT'],sym['BANK_PAGE_EXROM_IN']}
seen=set(); stack=[sym[t] for t in targets]; indirect=[]; unresolved=[]
while stack:
    a=stack.pop()
    while a in ins and a not in seen:
        seen.add(a)
        t,sc=ins[a]; op=t.split()[0].lower(); rest=t[len(op):].strip()
        if op in('call','jp','jr','djnz'):
            parts=[p.strip() for p in rest.split(',')]
            tg=parts[-1]; cond=len(parts)>1
            if tg.lower() in('(hl)','(ix)','(iy)'): indirect.append((hex(a),t,sc)); 
            else:
                r=resolve(tg,sc)
                if r is None: unresolved.append((hex(a),t,sc))
                else: stack.append(r)
            if op in('jp','jr') and not cond: break
        elif op in('ret','reti','retn'):
            if rest=='' : break
        elif op=='rst': indirect.append((hex(a),t,sc))
        a=nxt.get(a,-1)
reach=seen
print('instructions reachable from the 5 home-table targets:',len(seen))
print('EXROM_CALL_SLOT/BANK_PAGE_EXROM_IN reachable:',bool(seen&goal))
print('indirect transfers:',indirect[:10])
print('unresolved:',unresolved[:10])
names=sorted({ins[a][1] for a in seen})
print(len(names),'scopes e.g.',names[:30])
