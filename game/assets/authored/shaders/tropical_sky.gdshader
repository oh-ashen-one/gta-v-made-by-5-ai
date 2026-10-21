shader_type sky;
// Original static tropical-afternoon sky. No photographed skyline/backdrop.
uniform vec3 zenith : source_color = vec3(0.16, 0.34, 0.57);
uniform vec3 horizon : source_color = vec3(0.72, 0.76, 0.76);
uniform vec3 sun_direction = vec3(-0.55, 0.47, -0.69);
float hash3(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise3(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float fbm(vec3 p) {
 float n=0.0; float a=0.55;
 for(int i=0;i<5;i++){n+=noise3(p)*a;p=p*2.03+vec3(3.1,2.7,1.9);a*=0.48;}
 return n;
}
void sky() {
 vec3 ray=normalize(EYEDIR);
 float h=max(ray.y,0.0);
 vec3 col=mix(horizon,zenith,pow(h,0.48));
 vec3 sd=normalize(sun_direction);
 float facing=max(dot(ray,sd),0.0);
 col+=vec3(1.0,.59,.24)*pow(facing,12.0)*.20;
 if(ray.y>0.015){
  vec3 p=vec3(ray.x,ray.y*.7,ray.z)*3.5;
  float cloud=fbm(p+vec3(2.8,.4,-1.7));
  float cover=smoothstep(.50,.69,cloud)*smoothstep(.015,.11,h);
  float edge=fbm(p+sd*.24+vec3(2.8,.4,-1.7));
  vec3 shade=mix(vec3(.41,.48,.57),vec3(1.0,.92,.77),clamp(.50+(edge-cloud)*4.0,0.0,1.0));
  col=mix(col,shade,cover*.96);
 }
 float disk=smoothstep(.99994,.999975,facing);
 col+=vec3(1.0,.82,.53)*disk*6.0;
 if(ray.y<0.0) col=mix(horizon,vec3(.12,.15,.13),smoothstep(0.0,.3,-ray.y));
 COLOR=col;
}
