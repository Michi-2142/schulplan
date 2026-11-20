import sys
# App-Icon erzeugen: python3 Tools/make_app_icon.py <Zielordner>  → icon-light/dark/tinted.png (1024 px)
from PIL import Image, ImageDraw, ImageFilter
N=1024; K=4; W=N*K
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(len(a)))
def gradient(c1,c2):
    g=Image.new('RGB',(256,256))
    px=g.load()
    for y in range(256):
        for x in range(256):
            px[x,y]=lerp(c1,c2,(x+y)/510)
    return g.resize((W,W),Image.BICUBIC)
def rr(d,box,r,fill): d.rounded_rectangle([v*K for v in box],radius=r*K,fill=fill)

def make(mode, tint=False):
    if mode=='light':
        bg=gradient((70,120,250),(118,74,236)).convert('RGBA')
    elif mode=='dark':
        bg=gradient((22,28,64),(38,20,70)).convert('RGBA')
    else:
        bg=Image.new('RGBA',(W,W),(0,0,0,0)) if mode=='tinted' else None
    # weicher Glanz oben links
    if mode!='tinted':
        glow=Image.new('RGBA',(W,W),(0,0,0,0)); gd=ImageDraw.Draw(glow)
        gd.ellipse([-300*K,-360*K,700*K,560*K],fill=(255,255,255,46 if mode=='light' else 22))
        bg=Image.alpha_composite(bg,glow.filter(ImageFilter.GaussianBlur(120*K)))
    # Schatten der Karte
    card=(212,196,812,846)
    if mode!='tinted':
        sh=Image.new('RGBA',(W,W),(0,0,0,0)); sd=ImageDraw.Draw(sh)
        rr(sd,(card[0],card[1]+26,card[2],card[3]+26),118,(10,10,60,110 if mode=='light' else 160))
        bg=Image.alpha_composite(bg,sh.filter(ImageFilter.GaussianBlur(34*K)))
    layer=Image.new('RGBA',(W,W),(0,0,0,0)); d=ImageDraw.Draw(layer)
    if mode=='light':
        cardc=(255,255,255,255); head=(232,238,255,255); line=(214,220,236,255); dot=(198,206,228,255)
    elif mode=='dark':
        cardc=(44,48,82,255); head=(56,62,108,255); line=(84,90,132,255); dot=(96,104,150,255)
    else:
        cardc=(255,255,255,255); head=(255,255,255,140); line=(255,255,255,110); dot=(255,255,255,120)
    rr(d,card,118,cardc)
    # Kopf mit Wochentagen
    if mode=='tinted':
        rr(d,(card[0],card[1],card[2],card[1]+150),118,(0,0,0,0))
    d.rounded_rectangle([card[0]*K,card[1]*K,card[2]*K,(card[1]+150)*K],radius=118*K,fill=head,corners=(True,True,False,False))
    accent=(70,112,248,255) if mode!='tinted' else (255,255,255,255)
    xs=[302,407,512,617,722]
    for i,x in enumerate(xs):
        r=30
        fill=accent if i==2 else dot
        d.ellipse([(x-r)*K,(card[1]+75-r)*K,(x+r)*K,(card[1]+75+r)*K],fill=fill)
    # Stunden-Zeilen
    if mode=='tinted':
        cols=[(255,255,255,200)]*4; orange=(255,255,255,255)
    else:
        cols=[(124,92,246,255),(34,190,200,255),None,(62,196,120,255)]; orange=(255,149,0,255)
    rows=[400,500,600,700]; lens=[420,330,0,380]
    for i,y in enumerate(rows):
        if i==2:
            hl=(255,236,208,255) if mode=='light' else ((98,74,64,255) if mode=='dark' else (255,255,255,170))
            rr(d,(card[0]+36,y-40,card[2]-36,y+40),30,hl)
            rr(d,(card[0]+66,y-28,card[0]+84,y+28),9,orange)
            # durchgestrichene Stunde
            l=(card[0]+116,y-13,card[0]+116+300,y+13)
            rr(d,l,13,(255,196,120,255) if mode=='light' else ((214,128,42,255) if mode=='dark' else (255,255,255,255)))
        else:
            rr(d,(card[0]+66,y-28,card[0]+84,y+28),9,cols[i])
            rr(d,(card[0]+116,y-13,card[0]+116+lens[i],y+13),13,line)
    img=Image.alpha_composite(bg,layer) if bg is not None else layer
    # Hinweis-Plakette (Änderung) rechts an der Karte
    b=Image.new('RGBA',(W,W),(0,0,0,0)); bd=ImageDraw.Draw(b)
    cx,cy,R=790,600,104
    if mode!='tinted':
        sh=Image.new('RGBA',(W,W),(0,0,0,0)); ImageDraw.Draw(sh).ellipse([(cx-R)*K,(cy-R+16)*K,(cx+R)*K,(cy+R+16)*K],fill=(120,40,0,120))
        img=Image.alpha_composite(img,sh.filter(ImageFilter.GaussianBlur(22*K)))
    ring=(255,255,255,255) if mode=='light' else ((44,48,82,255) if mode=='dark' else (0,0,0,0))
    if mode!='tinted': bd.ellipse([(cx-R-14)*K,(cy-R-14)*K,(cx+R+14)*K,(cy+R+14)*K],fill=ring)
    bd.ellipse([(cx-R)*K,(cy-R)*K,(cx+R)*K,(cy+R)*K],fill=(255,255,255,255) if tint else orange)
    # Tauschpfeile ⇄ in weiß
    wc=(255,255,255,255) if mode!='tinted' else (0,0,0,0)
    if tint: wc=(30,30,40,255)
    def arrow(y,right):
        x0,x1=cx-50,cx+50
        rr(bd,(x0+(0 if right else 22),y-10,x1-(22 if right else 0),y+10),10,wc)
        tip=x1 if right else x0; back=tip-46 if right else tip+46
        bd.polygon([(tip*K,y*K),(back*K,(y-34)*K),(back*K,(y+34)*K)],fill=wc)
    arrow(cy-30,True); arrow(cy+30,False)
    img=Image.alpha_composite(img,b)
    out=img.resize((N,N),Image.LANCZOS)
    if mode!='tinted': out=out.convert('RGB')
    return out
for m in ['light','dark']:
    make(m).save(f'{sys.argv[1]}/icon-{m}.png')
# Getönte Variante: Graustufen der dunklen – das System färbt sie selbst ein.
from PIL import ImageOps
g=ImageOps.autocontrast(make('dark', tint=True).convert('L'), cutoff=1)
g.convert('RGB').save(f'{sys.argv[1]}/icon-tinted.png')
