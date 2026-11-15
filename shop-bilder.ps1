# Bereitet die Amazon-Bilder für den eigenen Shop auf:
# Text-Grafiken wegschneiden, einheitliches 4:5-Format, weißer Hintergrund der Freisteller -> warmes Hellgrau.
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Collections.Generic;
public static class Bg {
  // Füllt den weißen Hintergrund vom Bildrand aus mit einer Farbe (Flood-Fill, damit helle Stellen im Produkt bleiben)
  public static void Fill(Bitmap b, Color c, int tol) {
    int w = b.Width, h = b.Height;
    var d = b.LockBits(new Rectangle(0,0,w,h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    int n = w*h; var px = new int[n];
    System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, n);
    var seen = new bool[n]; var q = new Queue<int>();
    for (int x=0;x<w;x++){ q.Enqueue(x); q.Enqueue((h-1)*w+x); }
    for (int y=0;y<h;y++){ q.Enqueue(y*w); q.Enqueue(y*w+w-1); }
    int target = c.ToArgb();
    while (q.Count>0) {
      int i = q.Dequeue(); if (seen[i]) continue; seen[i]=true;
      int p = px[i]; int r=(p>>16)&255, g=(p>>8)&255, bl=p&255;
      if (r<255-tol || g<255-tol || bl<255-tol) continue;
      px[i]=target; int x=i%w, y=i/w;
      if (x>0) q.Enqueue(i-1); if (x<w-1) q.Enqueue(i+1); if (y>0) q.Enqueue(i-w); if (y<h-1) q.Enqueue(i+w);
    }
    System.Runtime.InteropServices.Marshal.Copy(px, 0, d.Scan0, n); b.UnlockBits(d);
  }

  // Einheitlicher Look: Weißabgleich auf warmes Leinen-Weiß, gleiche Helligkeit, etwas ruhigere Sättigung
  public static void Grade(Bitmap b, double wbStrength, double targetMean, double sat) {
    int w = b.Width, h = b.Height, n = w*h;
    var d = b.LockBits(new Rectangle(0,0,w,h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    var px = new int[n]; System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, n);
    var hist = new int[256];
    for (int i=0;i<n;i++){ int p=px[i]; hist[(int)(((p>>16)&255)*.299+((p>>8)&255)*.587+(p&255)*.114)]++; }
    int cut=255, acc=0; while (cut>0 && acc < n/10) { acc += hist[cut]; cut--; }
    double hr=0,hg=0,hb=0; int hc=0;
    for (int i=0;i<n;i++){ int p=px[i]; int r=(p>>16)&255,g=(p>>8)&255,bl=p&255;
      if (r*.299+g*.587+bl*.114 > cut){ hr+=r; hg+=g; hb+=bl; hc++; } }
    hr/=hc; hg/=hc; hb/=hc;
    double tr=242, tg=235, tb=226;                      // Ziel: warmes Weiß der Wände
    double kr=tr/hr, kg=tg/hg, kb=tb/hb, km=(kr+kg+kb)/3;
    kr = 1+(kr/km-1)*wbStrength; kg = 1+(kg/km-1)*wbStrength; kb = 1+(kb/km-1)*wbStrength;
    double sum=0;
    for (int i=0;i<n;i++){ int p=px[i]; sum += Math.Min(255,((p>>16)&255)*kr)*.299+Math.Min(255,((p>>8)&255)*kg)*.587+Math.Min(255,(p&255)*kb)*.114; }
    double mean = sum/n, gamma = 1;
    if (targetMean > 0) gamma = Math.Max(.8, Math.Min(1.25, Math.Log(targetMean/255)/Math.Log(mean/255)));
    var lut = new double[256]; for (int v=0; v<256; v++) lut[v] = 255*Math.Pow(v/255.0, gamma);
    for (int i=0;i<n;i++){
      int p=px[i];
      double r=lut[(int)Math.Min(255,((p>>16)&255)*kr)], g=lut[(int)Math.Min(255,((p>>8)&255)*kg)], bl=lut[(int)Math.Min(255,(p&255)*kb)];
      double L=r*.299+g*.587+bl*.114;
      r=L+(r-L)*sat; g=L+(g-L)*sat; bl=L+(bl-L)*sat;
      px[i] = (255<<24) | ((int)Math.Max(0,Math.Min(255,r))<<16) | ((int)Math.Max(0,Math.Min(255,g))<<8) | (int)Math.Max(0,Math.Min(255,bl));
    }
    System.Runtime.InteropServices.Marshal.Copy(px, 0, d.Scan0, n); b.UnlockBits(d);
  }

  static int[] Px(Bitmap b) {
    var d = b.LockBits(new Rectangle(0,0,b.Width,b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    var px = new int[b.Width*b.Height]; System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length); b.UnlockBits(d); return px;
  }
  static void Stats(int[] px, double[] m, double[] s) {
    for (int c=0;c<3;c++){ double sum=0, sq=0; int sh=16-8*c;
      foreach (int p in px){ double v=(p>>sh)&255; sum+=v; sq+=v*v; }
      m[c]=sum/px.Length; s[c]=Math.Sqrt(Math.Max(1, sq/px.Length-m[c]*m[c])); }
  }
  // Übernimmt Farbstimmung, Helligkeit und Kontrast (Mittelwert und Streuung je Farbkanal) von Referenzbildern
  public static void MatchTo(Bitmap b, Bitmap[] refs, double strength) {
    double[] rm=new double[3], rs=new double[3];
    foreach (var r in refs){ double[] m=new double[3], s=new double[3]; Stats(Px(r), m, s); for(int c=0;c<3;c++){ rm[c]+=m[c]/refs.Length; rs[c]+=s[c]/refs.Length; } }
    int w=b.Width, h=b.Height; var d = b.LockBits(new Rectangle(0,0,w,h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    var px = new int[w*h]; System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length);
    double[] tm=new double[3], ts=new double[3]; Stats(px, tm, ts);
    for (int i=0;i<px.Length;i++){ int p=px[i]; int[] o=new int[3];
      for (int c=0;c<3;c++){ int sh=16-8*c; double v=(p>>sh)&255; double nv=(v-tm[c])*(rs[c]/ts[c])+rm[c]; nv=v+(nv-v)*strength; o[c]=(int)Math.Max(0,Math.Min(255,nv)); }
      px[i]=(255<<24)|(o[0]<<16)|(o[1]<<8)|o[2]; }
    System.Runtime.InteropServices.Marshal.Copy(px, 0, d.Scan0, px.Length); b.UnlockBits(d);
  }
  // Entfernt Text auf ruhigem Hintergrund: füllt ein Rechteck durch Verlauf zwischen den Pixeln links/rechts (horizontal)
  // oder oben/unten (vertikal) außerhalb des Rechtecks
  public static void Erase(Bitmap b, int x0, int y0, int x1, int y1, bool horizontal) {
    int w=b.Width, h=b.Height; x0=Math.Max(1,x0); y0=Math.Max(1,y0); x1=Math.Min(w-2,x1); y1=Math.Min(h-2,y1);
    var d = b.LockBits(new Rectangle(0,0,w,h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    var px = new int[w*h]; System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length);
    Func<int,int,int> avg = (x,y) => { int r=0,g=0,bl=0,n=0; for(int dy=-2;dy<=2;dy++) for(int dx=-2;dx<=2;dx++){ int xx=Math.Max(0,Math.Min(w-1,x+dx)), yy=Math.Max(0,Math.Min(h-1,y+dy)); int p=px[yy*w+xx]; r+=(p>>16)&255; g+=(p>>8)&255; bl+=p&255; n++; } return (255<<24)|((r/n)<<16)|((g/n)<<8)|(bl/n); };
    var outPx = (int[])px.Clone();
    for (int y=y0;y<=y1;y++) for (int x=x0;x<=x1;x++) {
      int a, c; double t;
      if (horizontal) { a=avg(x0-3,y); c=avg(x1+3,y); t=(double)(x-x0)/Math.Max(1,x1-x0); }
      else { a=avg(x,y0-3); c=avg(x,y1+3); t=(double)(y-y0)/Math.Max(1,y1-y0); }
      int r=(int)(((a>>16)&255)*(1-t)+((c>>16)&255)*t), g=(int)(((a>>8)&255)*(1-t)+((c>>8)&255)*t), bl=(int)((a&255)*(1-t)+(c&255)*t);
      outPx[y*w+x]=(255<<24)|(r<<16)|(g<<8)|bl;
    }
    System.Runtime.InteropServices.Marshal.Copy(outPx, 0, d.Scan0, outPx.Length); b.UnlockBits(d);
  }

  // Leichtes Nachschärfen nach dem Hochskalieren (Unscharf maskieren mit 3x3-Weichzeichner)
  public static void Sharpen(Bitmap b, double amount) {
    int w=b.Width, h=b.Height; var d = b.LockBits(new Rectangle(0,0,w,h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    var px = new int[w*h]; System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length); var o=(int[])px.Clone();
    for (int y=1;y<h-1;y++) for (int x=1;x<w-1;x++){ int i=y*w+x; int[] rgb=new int[3];
      for (int c=0;c<3;c++){ int sh=16-8*c; double sum=0; for(int dy=-1;dy<=1;dy++) for(int dx=-1;dx<=1;dx++) sum+=(px[i+dy*w+dx]>>sh)&255;
        double v=(px[i]>>sh)&255; rgb[c]=(int)Math.Max(0,Math.Min(255, v+(v-sum/9)*amount)); }
      o[i]=(255<<24)|(rgb[0]<<16)|(rgb[1]<<8)|rgb[2]; }
    System.Runtime.InteropServices.Marshal.Copy(o, 0, d.Scan0, o.Length); b.UnlockBits(d);
  }

  // Bild oben und unten verlängern, ohne etwas abzuschneiden: Farbe = geglätteter Mittelwert eines
  // Randstreifens (Wand bzw. Teppich), Struktur = gespiegelte Kopie desselben Streifens
  public static Bitmap ExtendV(Bitmap b, int top, int bottom, int band) {
    int w=b.Width, h=b.Height, H=h+top+bottom;
    var d = b.LockBits(new Rectangle(0,0,w,h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    var px = new int[w*h]; System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length); b.UnlockBits(d);
    var o = new int[w*H]; Array.Copy(px, 0, o, top*w, px.Length);
    for (int side=0; side<2; side++) {
      int y0 = side==0 ? 0 : h-band, n = side==0 ? top : bottom;
      var mean = new double[w,3];
      for (int x=0;x<w;x++) for (int c=0;c<3;c++){ double s=0; for(int y=y0;y<y0+band;y++) s+=(px[y*w+x]>>(16-8*c))&255; mean[x,c]=s/band; }
      var sm = new double[w,3]; int r=24;
      for (int x=0;x<w;x++) for (int c=0;c<3;c++){ double s=0; int k=0; for(int j=Math.Max(0,x-r);j<=Math.Min(w-1,x+r);j++){ s+=mean[j,c]; k++; } sm[x,c]=s/k; }
      for (int i=1;i<=n;i++) {
        int p=(i-1)%(2*band); int srcRow = p<band ? p : 2*band-1-p;           // Ping-Pong durch den Streifen
        int sy = side==0 ? y0+srcRow : y0+band-1-srcRow;
        int ty = side==0 ? top-i : top+h-1+i;
        double fade = Math.Min(1.0, i/(double)band);                           // am Übergang Originalfarbe, weiter weg geglättet
        for (int x=0;x<w;x++){ int[] rgb=new int[3];
          for (int c=0;c<3;c++){ int sh=16-8*c; double v=(px[sy*w+x]>>sh)&255; double res=v-mean[x,c];
            double baseV = mean[x,c]*(1-fade)+sm[x,c]*fade; rgb[c]=(int)Math.Max(0,Math.Min(255, baseV+res)); }
          o[ty*w+x]=(255<<24)|(rgb[0]<<16)|(rgb[1]<<8)|rgb[2]; }
      }
    }
    var nb = new Bitmap(w, H, PixelFormat.Format32bppArgb);
    var nd = nb.LockBits(new Rectangle(0,0,w,H), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    System.Runtime.InteropServices.Marshal.Copy(o, 0, nd.Scan0, o.Length); nb.UnlockBits(nd); return nb;
  }

  static void Put(Bitmap b, int[] px) {
    var d = b.LockBits(new Rectangle(0,0,b.Width,b.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    System.Runtime.InteropServices.Marshal.Copy(px, 0, d.Scan0, px.Length); b.UnlockBits(d);
  }
  static double Lum(int p) { return ((p>>16)&255)*.299+((p>>8)&255)*.587+(p&255)*.114; }

  // Entfernt aufgedruckte Schrift: in jedem Rechteck (x0,y0,x1,y1) die dunkle Schrift per Otsu-Schwelle finden,
  // die Maske etwas erweitern und nur diese Pixel aus der Umgebung auffuellen (Laplace). Der echte Hintergrund
  // zwischen den Buchstaben bleibt erhalten, deshalb sieht man die Stelle danach nicht.
  public static void Inpaint(Bitmap b, int[] rects, int dilate, double lean) {
    int w=b.Width, h=b.Height; var px = Px(b); var mask = new bool[w*h];
    for (int k=0; k+3<rects.Length; k+=4) {
      int x0=Math.Max(0,rects[k]), y0=Math.Max(0,rects[k+1]), x1=Math.Min(w-1,rects[k+2]), y1=Math.Min(h-1,rects[k+3]);
      var hist = new int[256]; int n=0;
      for (int y=y0;y<=y1;y++) for (int x=x0;x<=x1;x++){ hist[(int)Lum(px[y*w+x])]++; n++; }
      double sumAll=0; for (int i=0;i<256;i++) sumAll += i*hist[i];
      double sumB=0, wB=0, best=-1; int t=0;
      for (int i=0;i<256;i++){ wB+=hist[i]; if (wB==0) continue; double wF=n-wB; if (wF==0) break; sumB+=i*hist[i];
        double mB=sumB/wB, mF=(sumAll-sumB)/wF, v=wB*wF*(mB-mF)*(mB-mF); if (v>best){ best=v; t=i; } }
      double tm=0; int tn=0, bn=0; for (int i=0;i<=t;i++){ tm+=i*hist[i]; tn+=hist[i]; } tm/=Math.Max(1,tn);
      for (int i=t+1;i<256;i++) bn+=hist[i];
      int acc=0, med=255; for (int i=t+1;i<256;i++){ acc+=hist[i]; if (acc>=bn/2){ med=i; break; } }
      if (med - tm < 25) continue;                                   // kein klarer Kontrast: hier steht keine Schrift
      double T = t + (med - t)*lean;
      for (int y=y0;y<=y1;y++) for (int x=x0;x<=x1;x++) if (Lum(px[y*w+x]) < T) mask[y*w+x]=true;
    }
    var m2 = new bool[w*h];
    for (int y=0;y<h;y++) for (int x=0;x<w;x++) if (mask[y*w+x])
      for (int dy=-dilate;dy<=dilate;dy++) for (int dx=-dilate;dx<=dilate;dx++){ int xx=x+dx, yy=y+dy; if (xx>=0&&yy>=0&&xx<w&&yy<h) m2[yy*w+xx]=true; }
    mask = m2;
    var ch = new double[3][]; for (int c=0;c<3;c++){ ch[c]=new double[w*h]; int sh=16-8*c; for (int i=0;i<w*h;i++) ch[c][i]=(px[i]>>sh)&255; }
    var todo = (bool[])mask.Clone(); bool any=true; int guard=0;     // Startwert von aussen nach innen
    while (any && guard++ < 400) { any=false; var next=(bool[])todo.Clone();
      for (int y=0;y<h;y++) for (int x=0;x<w;x++){ int i=y*w+x; if (!todo[i]) continue; double[] s=new double[3]; int cnt=0;
        if (x>0 && !todo[i-1]){ for(int c=0;c<3;c++) s[c]+=ch[c][i-1]; cnt++; }
        if (x<w-1 && !todo[i+1]){ for(int c=0;c<3;c++) s[c]+=ch[c][i+1]; cnt++; }
        if (y>0 && !todo[i-w]){ for(int c=0;c<3;c++) s[c]+=ch[c][i-w]; cnt++; }
        if (y<h-1 && !todo[i+w]){ for(int c=0;c<3;c++) s[c]+=ch[c][i+w]; cnt++; }
        if (cnt>0){ for(int c=0;c<3;c++) ch[c][i]=s[c]/cnt; next[i]=false; } else any=true; }
      todo=next; }
    for (int it=0; it<500; it++) for (int y=0;y<h;y++) for (int x=0;x<w;x++){ int i=y*w+x; if (!mask[i]) continue;
      for (int c=0;c<3;c++){ double s=0; int cnt=0;
        if (x>0){ s+=ch[c][i-1]; cnt++; } if (x<w-1){ s+=ch[c][i+1]; cnt++; } if (y>0){ s+=ch[c][i-w]; cnt++; } if (y<h-1){ s+=ch[c][i+w]; cnt++; }
        ch[c][i] += 1.6*(s/cnt - ch[c][i]); } }
    var rnd = new Random(7);                                          // feines Korn wie im restlichen Bild
    for (int i=0;i<w*h;i++) if (mask[i]) {
      double g = (rnd.NextDouble()+rnd.NextDouble()+rnd.NextDouble()-1.5)*2.2;
      int r=(int)Math.Max(0,Math.Min(255,ch[0][i]+g)), gg=(int)Math.Max(0,Math.Min(255,ch[1][i]+g)), bl=(int)Math.Max(0,Math.Min(255,ch[2][i]+g));
      px[i]=(255<<24)|(r<<16)|(gg<<8)|bl; }
    Put(b, px);
  }

  static double[] Grad(int[] px, int w, int h) {
    var L = new double[w*h]; for (int i=0;i<w*h;i++) L[i]=Lum(px[i]);
    var g = new double[w*h];
    for (int y=1;y<h-1;y++) for (int x=1;x<w-1;x++){ int i=y*w+x;
      double gx = L[i-w+1]+2*L[i+1]+L[i+w+1]-L[i-w-1]-2*L[i-1]-L[i+w-1];
      double gy = L[i+w-1]+2*L[i+w]+L[i+w+1]-L[i-w-1]-2*L[i-w]-L[i-w+1];
      g[i]=Math.Sqrt(gx*gx+gy*gy); }
    return g;
  }
  static double[] Half(double[] a, int w, int h) {
    int w2=w/2, h2=h/2; var o=new double[w2*h2];
    for (int y=0;y<h2;y++) for (int x=0;x<w2;x++) o[y*w2+x]=(a[2*y*w+2*x]+a[2*y*w+2*x+1]+a[(2*y+1)*w+2*x]+a[(2*y+1)*w+2*x+1])/4;
    return o;
  }
  static double Score(double[] A, double[] B, int w, int h, double sx, double sy, double tx, double ty) {
    double cx=w/2.0, cy=h/2.0; int m=(int)(Math.Min(w,h)*0.06);
    double sa=0,sb=0,saa=0,sbb=0,sab=0; int n=0;
    for (int y=m;y<h-m;y++){ double v=cy+(y-cy)*sy+ty; int y0=(int)Math.Floor(v); if (y0<0||y0>=h-1) continue; double fy=v-y0;
      for (int x=m;x<w-m;x++){ double u=cx+(x-cx)*sx+tx; int x0=(int)Math.Floor(u); if (x0<0||x0>=w-1) continue; double fx=u-x0;
        int i=y0*w+x0; double b=(B[i]*(1-fx)+B[i+1]*fx)*(1-fy)+(B[i+w]*(1-fx)+B[i+w+1]*fx)*fy; double a=A[y*w+x];
        sa+=a; sb+=b; saa+=a*a; sbb+=b*b; sab+=a*b; n++; } }
    if (n<100) return -1;
    double cov=sab/n-(sa/n)*(sb/n), va=saa/n-(sa/n)*(sa/n), vb=sbb/n-(sb/n)*(sb/n);
    return cov/Math.Sqrt(Math.Max(1e-9,va*vb));
  }
  // Sucht Massstab und Verschiebung, mit denen Bild b deckungsgleich auf Bild a liegt (Vergleich der Kanten, grob nach fein).
  // Ergebnis: sx, sy, tx, ty, Uebereinstimmung
  public static double[] Register(Bitmap a, Bitmap b) {
    int w=a.Width, h=a.Height; var A1=Grad(Px(a),w,h); var B1=Grad(Px(b),w,h);
    var A2=Half(A1,w,h); var B2=Half(B1,w,h); int w2=w/2,h2=h/2; var A4=Half(A2,w2,h2); var B4=Half(B2,w2,h2); int w4=w2/2,h4=h2/2;
    double bs=1,bx=0,by=0,best=-2;
    for (double s=0.94;s<=1.0601;s+=0.01) for (double ty=-10;ty<=10;ty+=1) for (double tx=-10;tx<=10;tx+=1){ double v=Score(A4,B4,w4,h4,s,s,tx,ty); if (v>best){best=v;bs=s;bx=tx;by=ty;} }
    bx*=2; by*=2; double s0=bs,x0=bx,y0=by; best=-2;
    for (double s=s0-0.01;s<=s0+0.0101;s+=0.0025) for (double ty=y0-2;ty<=y0+2;ty+=0.5) for (double tx=x0-2;tx<=x0+2;tx+=0.5){ double v=Score(A2,B2,w2,h2,s,s,tx,ty); if (v>best){best=v;bs=s;bx=tx;by=ty;} }
    bx*=2; by*=2; s0=bs; x0=bx; y0=by; best=-2; double bsx=bs,bsy=bs;
    for (double sx=s0-0.0075;sx<=s0+0.0076;sx+=0.0025) for (double sy=s0-0.0075;sy<=s0+0.0076;sy+=0.0025)
      for (double ty=y0-2;ty<=y0+2;ty+=1) for (double tx=x0-2;tx<=x0+2;tx+=1){ double v=Score(A1,B1,w,h,sx,sy,tx,ty); if (v>best){best=v;bsx=sx;bsy=sy;bx=tx;by=ty;} }
    return new double[]{bsx,bsy,bx,by,best};
  }
  // Tastet Bild b mit der gefundenen Abbildung neu ab (bilinear)
  public static Bitmap Warp(Bitmap b, double sx, double sy, double tx, double ty) {
    int w=b.Width, h=b.Height; var px=Px(b); var o=new int[w*h]; double cx=w/2.0, cy=h/2.0;
    for (int y=0;y<h;y++){ double v=Math.Max(0,Math.Min(h-1.001,cy+(y-cy)*sy+ty)); int y0=(int)v; double fy=v-y0;
      for (int x=0;x<w;x++){ double u=Math.Max(0,Math.Min(w-1.001,cx+(x-cx)*sx+tx)); int x0=(int)u; double fx=u-x0; int i=y0*w+x0; int res=255<<24;
        for (int c=0;c<3;c++){ int sh=16-8*c; double val=(((px[i]>>sh)&255)*(1-fx)+((px[i+1]>>sh)&255)*fx)*(1-fy)+(((px[i+w]>>sh)&255)*(1-fx)+((px[i+w+1]>>sh)&255)*fx)*fy; res|=((int)(val+.5))<<sh; }
        o[y*w+x]=res; } }
    var nb=new Bitmap(w,h,PixelFormat.Format32bppArgb); Put(nb,o); return nb;
  }
}
"@

$src = Join-Path $PSScriptRoot 'img'
$out = Join-Path $PSScriptRoot 'img\shop'
New-Item -ItemType Directory -Force $out | Out-Null
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 86L
$stage = [System.Drawing.Color]::FromArgb(255, 230, 226, 218)

function Save-Crop($name, $file, $x, $y, $w, $h) {
  $im = [System.Drawing.Image]::FromFile((Join-Path $src $file))
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage($im, (New-Object System.Drawing.Rectangle 0, 0, $w, $h), (New-Object System.Drawing.Rectangle $x, $y, $w, $h), 'Pixel')
  $bmp.Save((Join-Path $out "$name.jpg"), $enc, $ep); $g.Dispose(); $bmp.Dispose(); $im.Dispose()
}
# Mittiger 4:5-Zuschnitt
function Save-Portrait($name, $file) {
  $im = [System.Drawing.Image]::FromFile((Join-Path $src $file)); $W = $im.Width; $H = $im.Height; $im.Dispose()
  if ($W / $H -gt 0.8) { $w = [int]($H * 0.8); Save-Crop $name $file ([int](($W - $w) / 2)) 0 $w $H }
  else { $h = [int]($W / 0.8); Save-Crop $name $file 0 ([int](($H - $h) / 2)) $W $h }
}
# Freisteller auf Hellgrau, 4:5 mit Luft drumherum
function Save-Packshot($name, $file) {
  $im = New-Object System.Drawing.Bitmap (Join-Path $src $file)
  $b = $im.Clone((New-Object System.Drawing.Rectangle 0, 0, $im.Width, $im.Height), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  [Bg]::Fill($b, $stage, 14)
  $W = [int]($b.Width * 1.0); $H = [int]($W * 1.25)
  $canvas = New-Object System.Drawing.Bitmap $W, $H
  $g = [System.Drawing.Graphics]::FromImage($canvas); $g.Clear($stage); $g.InterpolationMode = 'HighQualityBicubic'
  $s = 0.86; $dw = [int]($b.Width * $s); $dh = [int]($b.Height * $s)
  $g.DrawImage($b, [int](($W - $dw) / 2), [int](($H - $dh) / 2), $dw, $dh)
  $canvas.Save((Join-Path $out "$name.jpg"), $enc, $ep); $g.Dispose(); $canvas.Dispose(); $b.Dispose(); $im.Dispose()
}

function Load32($path) {
  $im = New-Object System.Drawing.Bitmap $path
  $b = $im.Clone((New-Object System.Drawing.Rectangle 0, 0, $im.Width, $im.Height), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb); $im.Dispose(); $b
}
function Resize($bmp, $w, $h) {
  $o = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($o); $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
  $g.DrawImage($bmp, 0, 0, $w, $h); $g.Dispose(); $o
}

# Wohnzimmer-Banner (Amazon A+): aufgedruckte Schrift entfernen. Je Textzeile ein Rechteck x0, y0, x1, y1.
$clean = Join-Path $src 'clean'; New-Item -ItemType Directory -Force $clean | Out-Null
$textAreas = @{
  'aplus-1' = @(628,478,969,599)
  'aplus-3' = @(628,470,969,599)
  'aplus-2' = @(612,30,956,80,  612,80,782,108,  634,142,969,178,  634,204,950,240,  634,264,840,298)
  'aplus-4' = @(503,32,916,76,  503,74,646,100,  526,166,756,206,  526,210,702,250,  526,254,752,294,  528,328,882,366,  528,376,782,414,  528,426,897,464)
}
foreach ($n in $textAreas.Keys) {
  $b = Load32 (Join-Path $src "$n.jpg"); [Bg]::Inpaint($b, [int[]]$textAreas[$n], 2, 0.45)
  $b.Save((Join-Path $clean "$n.png")); $b.Dispose()
}

# Startbild: dasselbe Wohnzimmer in Beige und Grau. Das graue Bild wird deckungsgleich auf das beige gelegt,
# beide auf den gemeinsamen Ausschnitt geschnitten, doppelt so groß gerechnet und nachgeschärft.
$a = Load32 (Join-Path $clean 'aplus-1.png'); $g0 = Load32 (Join-Path $clean 'aplus-3.png')
$r = [Bg]::Register($a, $g0); $gw = [Bg]::Warp($g0, $r[0], $r[1], $r[2], $r[3]); $g0.Dispose()
$W = $a.Width; $H = $a.Height; $cx = $W / 2; $cy = $H / 2
$x0 = [Math]::Max(0, [Math]::Ceiling($cx - ($cx + $r[2]) / $r[0])) + 1; $x1 = [Math]::Min($W - 1, [Math]::Floor($cx + ($W - 1 - $cx - $r[2]) / $r[0])) - 1
$y0 = [Math]::Max(0, [Math]::Ceiling($cy - ($cy + $r[3]) / $r[1])) + 1; $y1 = [Math]::Min($H - 1, [Math]::Floor($cy + ($H - 1 - $cy - $r[3]) / $r[1])) - 1
$rc = New-Object System.Drawing.Rectangle ([int]$x0), ([int]$y0), ([int]($x1 - $x0 + 1)), ([int]($y1 - $y0 + 1))
"Startbild: Massstab $('{0:F4}' -f $r[0]) / $('{0:F4}' -f $r[1]), Versatz $($r[2]) / $($r[3]), Deckung $('{0:F2}' -f $r[4]), Ausschnitt $($rc.Width)x$($rc.Height)"
foreach ($p in @(@('beige', $a), @('grau', $gw))) {
  $cut = $p[1].Clone($rc, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $big = Resize $cut ($rc.Width * 2) ($rc.Height * 2); $cut.Dispose()
  if ($p[0] -eq 'grau') { [Bg]::Grade($big, 0.7, 0, 0.7) } else { [Bg]::Grade($big, 0.8, 0, 0.9) }   # Grau neutraler halten, sonst wirkt es fliederfarben
  [Bg]::Sharpen($big, 0.5)
  $big.Save((Join-Path $out "$($p[0])-hero.jpg"), $enc, $ep); $big.Dispose()
}
$a.Dispose(); $gw.Dispose()

# Echtes Produktfoto (Amazon-Hauptbild) für die Lupe: weißer Hintergrund bleibt, die Seite legt es per "multiply" auf ihre Fläche.
# Dazu ein Stoffmuster aus der Seitenwand der vorderen Box für die Farbauswahl.
foreach ($c in 'beige', 'grau') {
  $b = Load32 (Join-Path $src "$c-1.jpg"); [Bg]::Grade($b, 0, 0, 0.9)
  $b.Save((Join-Path $out "$c-pack.jpg"), $enc, $ep)
  $sw = $b.Clone((New-Object System.Drawing.Rectangle 150, 860, 230, 230), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $small = Resize $sw 200 200; $small.Save((Join-Path $out "$c-stoff.jpg"), $enc, $ep); $small.Dispose(); $sw.Dispose(); $b.Dispose()
}

foreach ($c in 'beige', 'grau') {
  Save-Packshot "$c-set" "$c-1.jpg"
  Save-Portrait "$c-bad" "$c-4.jpg"
  $im = [System.Drawing.Image]::FromFile((Join-Path $src "$c-5.jpg")); $W = $im.Width; $H = $im.Height; $im.Dispose()
  # Arbeitszimmer komplett, ohne Zuschnitt: quadratisches Foto oben um freie Wand auf 4:5 verlängert
  # (unten nicht: im Teppich-Streifen steht ein Stuhlrad, das sich sonst spiegeln würde)
  $im = New-Object System.Drawing.Bitmap (Join-Path $src "$c-5.jpg")
  $b = $im.Clone((New-Object System.Drawing.Rectangle 0, 0, $W, $H), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb); $im.Dispose()
  $ext = [Bg]::ExtendV($b, [int]($W * 1.25) - $H, 0, [int]($H * 0.05)); $b.Dispose()
  $ext.Save((Join-Path $out "$c-buero.jpg"), $enc, $ep); $ext.Dispose()
  $im = [System.Drawing.Image]::FromFile((Join-Path $src "$c-6.jpg")); $W6 = $im.Width; $H6 = $im.Height; $im.Dispose()
  Save-Crop "$c-schlafzimmer" "$c-6.jpg" ($W6 - [int]($H6 * 0.8)) 0 ([int]($H6 * 0.8)) $H6   # rechtsbündig: der Schrank mit den Boxen ist ganz im Bild
  Save-Crop "$c-regal" "$c-7.jpg" 525 85 495 619       # nur die aufgeräumte Seite, ohne Überschrift
  Save-Crop "$c-detail" "$c-2.jpg" 0 175 520 650       # Nahaufnahme, ohne Icons und Banner
}
Save-Crop 'beige-wohnzimmer' 'clean\aplus-2.png' 145 0 480 600  # aus dem Bild ohne Schrift
Save-Crop 'grau-wohnzimmer' 'clean\aplus-4.png' 20 0 480 600
Remove-Item (Join-Path $out 'hero.jpg') -ErrorAction SilentlyContinue   # Startbild ist jetzt ein Bildpaar aus den Schlafzimmer-Fotos

# Farbangleichung: Raumfotos voll, Freisteller nur ruhigere Sättigung (Hintergrund bleibt Hellgrau)
foreach ($f in Get-ChildItem $out -Filter *.jpg) {
  if ($f.Name -match '-(hero|pack|stoff)\.jpg$') { continue }   # oben schon fertig bearbeitet
  $im = New-Object System.Drawing.Bitmap $f.FullName
  $b = $im.Clone((New-Object System.Drawing.Rectangle 0, 0, $im.Width, $im.Height), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $im.Dispose()
  if ($f.Name -like '*-set.jpg') { [Bg]::Grade($b, 0, 0, 0.9) }
  elseif ($f.Name -like '*-griff.jpg' -or $f.Name -like '*-gewebe.jpg') { [Bg]::Grade($b, 0, 0, 0.95) }   # Nahaufnahmen ohne Wand: kein Weißabgleich
  else { [Bg]::Grade($b, 0.8, 172, 0.85) }
  $tmp = "$($f.FullName).tmp"; $b.Save($tmp, $enc, $ep); $b.Dispose()
  Move-Item -Force $tmp $f.FullName
}
# Wohnzimmer-Bilder (aus kleinen Amazon-Bannern) an Bad und Arbeitszimmer angleichen:
# gleiche Größe wie die anderen (819x1024), Farbe/Helligkeit/Kontrast übernehmen, nachschärfen
foreach ($c in 'beige', 'grau') {
  $wz = Join-Path $out "$c-wohnzimmer.jpg"
  $im = New-Object System.Drawing.Bitmap $wz
  $big = New-Object System.Drawing.Bitmap 819, 1024, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($big); $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
  $g.DrawImage($im, 0, 0, 819, 1024); $g.Dispose(); $im.Dispose()
  $refs = @((New-Object System.Drawing.Bitmap (Join-Path $out "$c-bad.jpg")), (New-Object System.Drawing.Bitmap (Join-Path $out "$c-buero.jpg")))
  [Bg]::MatchTo($big, $refs, 0.9); [Bg]::Sharpen($big, 0.6)
  $refs | ForEach-Object { $_.Dispose() }
  $tmp = "$wz.tmp"; $big.Save($tmp, $enc, $ep); $big.Dispose(); Move-Item -Force $tmp $wz
}
# Größen-Bilder (S, L, XXL): Amazon-Überschrift und "Ideal für"-Liste entfernen, Maßpfeile behalten.
# Bereiche als Anteil der Bildgröße: Titel = [y0, y1], Liste = [x0, y0, x1, y1]
$sizeAreas = @{
  's'   = @{ title = @(0.035, 0.110); list = @(0.676, 0.185, 0.995, 0.775) }
  'l'   = @{ title = @(0.030, 0.090); list = @(0.748, 0.120, 0.997, 0.435) }
  'xxl' = @{ title = @(0.025, 0.090); list = @(0.665, 0.135, 0.985, 0.385) }
}
foreach ($c in 'beige', 'grau') { foreach ($s in 's', 'l', 'xxl') {
  $im = New-Object System.Drawing.Bitmap (Join-Path $src "$c-$s.jpg")
  $b = $im.Clone((New-Object System.Drawing.Rectangle 0, 0, $im.Width, $im.Height), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb); $im.Dispose()
  $W = $b.Width; $H = $b.Height; $a = $sizeAreas[$s]
  [Bg]::Erase($b, 0, [int]($a.title[0]*$H), $W, [int]($a.title[1]*$H), $false)
  [Bg]::Erase($b, [int]($a.list[0]*$W), [int]($a.list[1]*$H), $W, [int]($a.list[3]*$H), $true)
  [Bg]::Grade($b, 0.8, 172, 0.85)
  $b.Save((Join-Path $out "groesse-$c-$s.jpg"), $enc, $ep); $b.Dispose()
} }
Get-ChildItem $out | Select-Object Name, Length
