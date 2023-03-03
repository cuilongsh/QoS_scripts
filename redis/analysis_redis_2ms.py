from __future__ import division
import os
import sys,getopt
from prettytable import PrettyTable

def GetQPSAndLat(rootPath,QPS, Lat):
    for catogery in range(1,5):
        QPSTmp = 0
        LatTmp = 0
        path = rootPath + "/" + str(catogery)
        files = os.listdir(path)
        fileNum = 0
        fileNumReal = 0
        for file in files:
            if not os.path.isdir(file):
                filetoparse = path+"/" + file
                f = open(filetoparse, 'r')
                #print(filetoparse)
                for line in open(filetoparse):
                    line = f.readline()
                    linefield = line.split(' ')
                    while '' in linefield:
                        linefield.remove('')
                    #if linefield[0] == "[RUN":
                        #print(file,linefield[0],linefield[1],linefield[4])
                    if linefield[0] == "Totals":
                        print(file,linefield[0],linefield[1],linefield[4],fileNumReal)
                        if linefield[1] != "" and linefield[4] != "":
                            QPSTmp += float(linefield[1])
                            LatTmp += float(linefield[4])
                            fileNumReal = fileNumReal+1
                        fileNum += 1
                    #else:
                    #   print(file,linefield[0])
                f.close()
        print(fileNumReal)
        LatTmp = (LatTmp /fileNumReal)
        QPSTmp = (QPSTmp /fileNumReal)*fileNum
        QPS.append(QPSTmp)
        Lat.append(LatTmp)

def GetCPUUtilization(rootPath,CPUUti):
    path = rootPath + "/" + "cpuutil"
    files = os.listdir(path)
    for fileIndex in range(1, len(files)+1):
        file = "test" + str(fileIndex) + "-cpu.log"
        if not os.path.isdir(file):
            cpuIdel = 0
            coreNum = 0
            filetoparse = path+"/" + file
            f = open(filetoparse, 'r')
            for line in open(filetoparse):
                line = f.readline()
                linefield = line.split(' ')
                #if  linefield.count > 3:
                #    print(linefield[0],linefield[1])
                    #if linefield[0] == "Average:" and linefield[5] != "CPU":
                if linefield[0] == "Average:" and linefield[-1] != "%idle\n":
                    print(linefield[0],linefield[1],linefield[-1])
                    print(linefield[0],coreNum,cpuIdel)
                    #cpuIdel += float(linefield[-1].decode('UTF-8', 'ignore').strip().strip(b'\x00'.decode()))
                    cpuIdel += float(linefield[-1])
                    coreNum += 1
            f.close()
            print(coreNum,cpuIdel,file)
            cpuIdel = cpuIdel/float(coreNum)
            CPUUti.append(100-cpuIdel)

def main(argv):

    inputfolder = ''
    try:
      opts, args = getopt.getopt(argv,"hi:",["ifile="])
    except getopt.GetoptError:
      print('.py -i <inputfolder>') 
      sys.exit(2)
    for opt, arg in opts:
      if opt == '-h':
         print('.py -i <inputfolder>') 
         sys.exit()
      elif opt in ("-i", "--ifolder"):
         inputfolder = arg

    log_rootPath = os.getcwd() + "/"+inputfolder

    print('inputfolder',inputfolder) 
    TestDesc=[]
    TestDesc.append("baseline test-only hp")
    TestDesc.append("colocation-hp with lp noise")
    TestDesc.append("MBA-hp with lp noise")
    TestDesc.append("DRC-hp with lp noise")
    QPS=[]
    Lat=[]
    CPUUti=[]
    GetQPSAndLat(log_rootPath,QPS, Lat)
    GetCPUUtilization(log_rootPath,CPUUti)
    table = PrettyTable(['Test number','Description', 'QPS','Latency(ms)','CPU Utilization(%)'])
    for i in range(0, 4):
    #for i in range(0, 1):
        print(QPS,CPUUti)
        table.add_row([i+1, TestDesc[i], QPS[i], Lat[i], CPUUti[i]])

    print(table)
    print("Summary:")
    print("1. With noisy aggressor bwaves, DRC can maintain %s%% of the redis baseline performance by controlling bwaves memory access" % str(QPS[i]/QPS[0]))
    print("2. Overall CPU utilization is pushed to %s%% compared to %s%% with redis alone" % (CPUUti[0], CPUUti[2]))

if __name__ == "__main__":
    main(sys.argv[1:])
