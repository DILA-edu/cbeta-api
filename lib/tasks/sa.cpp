/* 
演算法：
  http://www.csie.ntnu.edu.tw/~u91029/StringSearching2.html
  http://www.csie.ntnu.edu.tw/~u91029/StringMatching2.html#2
2015.10.24 by Ray Chou
*/
#include <stdio.h>
#include <string.h>
#include <iostream>
#include <fstream>
#include <algorithm>    // std::sort
#include <time.h>

using namespace std;

string now() {
  time_t t = time(0);   // get time now
  return ctime(&t);  
}

void print_now() {
  time_t t = time(0);   // get time now
  cout << ctime(&t);  
}

void print_time(double t) {
  int s = t;
  printf("spend time: ");
  if (s > 60) {
    int m = s/60;
    s %= 60;
    if (m > 60) {
      printf("%d hours ", m/60);
      m %= 60;
    }
    printf("%d mins ", s/60);
  }
  printf("%d secs\n", s);
}

struct CMP {
  unsigned int* rank, n, N;
  bool operator()(const int& i, const int& j) {
    // 先比前半段
    if (rank[i] != rank[j])
      return rank[i] < rank[j];
    // 再比後半段
    int a = (i+n<N) ? rank[i+n] : -1;
    int b = (j+n<N) ? rank[j+n] : -1;
    return a < b;
  }
};

void suffix_array(char *arg, string dir) {
  std::cout << "sa.cpp: begin suffix_array(), dir: " << dir << "\n";
  std::string base;
  base.assign(arg);
  base += '/';
  
  string fn_text, fn_sa, fn_lcpa;
  ifstream f_text, f_sa;

  if (dir=="f") {
    fn_text = base + "all.txt";
    fn_sa = base + "sa.dat";
  } else {
    fn_text = base + "all-b.txt";
    fn_sa = base + "sa-b.dat";
  }
  std::cout << "fn_sa: " << fn_sa << "\n";

  // 開檔並移至檔尾
  f_text.open(fn_text, ios::binary|ios::ate);
  streampos size_in_bytes = f_text.tellg();
  unsigned int N = size_in_bytes / 4;
  // cout << "size is: " << size_in_bytes << " bytes.\n";
  // cout << "size is: " << N << " chars.\n";

  unsigned int* t = new unsigned int[N];
  unsigned int* rank = new unsigned int[N];
  unsigned int* new_rank = new unsigned int[N];
  unsigned int* sa = new unsigned int[N];

  // 讀入全部文字
  f_text.seekg (0, ios::beg);
  f_text.read((char*)t, size_in_bytes);
  f_text.close();
  
  /* 第一回合：字元個數為1。 */
 
  // sa 最後是排序後的 suffix index
  // 先把每一個 suffix index 依序寫入 sa
  for (int i=0; i<N; i++) sa[i] = i;
  
  // rank 放的是每個 suffix index 對應的名次
  // 第一個合以文字內碼當作名次。
  // cout << "first round\n";
  //for (int i=0; i<N; i++) rank[i] = t[i];
  memcpy(rank, t, size_in_bytes);
  
  /* 第二回合 以前2個字元排序，
     第三回合 以前4個字元排序，依此類推。不斷倍增。 */
 
  for (unsigned int m=2; m<=N; m*=2) {
    // cout << dir << m << endl << flush;
    // 運用上回合的名次，排序所有後綴。
    // 每個後綴，拿前m個字元，先比前半段、再比後半段。
    CMP cmp = {rank, m/2, N};
    sort(sa, sa+N, cmp);
 
    /* 
    把名次整理到 new_rank
    「前m個字元」相同的，名次設為相同，因為目前只比到「前m個字元」。
    因為這過程會使用到 rank array, 所以先整理到 new_rank,
    整理完再將結果放到 rank array.
    */
    int r = 0;
    new_rank[sa[0]] = r;
    for (int i=1; i<N; i++) {
      // 「前m個字元」相異者，名次加一；相同者，名次一樣。
      if (cmp(sa[i-1], sa[i])) r++;
      // 設定名次。
      new_rank[sa[i]] = r;
    }
    swap(rank, new_rank); // 把整理後的新名次存到 rank
 
    // 如果名次皆相異，表示排序完畢，提早結束演算法。
    if (r == N-1) break;
  }  
  ofstream myFile;
  myFile.open (fn_sa, ios::out | ios::binary);
  myFile.write ((char*)sa, size_in_bytes);
  myFile.close();
  std::cout << "sa.cpp: end of suffix_array()\n";
}

int main(int argc, char* argv[])
{    
  // std::cout << argv[1] << std::endl;
  
  time_t start_t, end_t;
  time(&start_t);
  
  suffix_array(argv[1], "b");
  suffix_array(argv[1], "f");

  time(&end_t);
  double diff_t = difftime(end_t, start_t);
  // print_time(diff_t);
  
  return 0;
}