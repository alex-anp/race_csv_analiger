#! /usr/local/bin/python3

import argparse
import csv
import datetime
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


import numpy as np


def read_data(csv_path):
   print('Will read data in file ' + csv_path)
   data = {}
   with open(csv_path, newline='') as csv_file:
      csv_reader = csv.DictReader(csv_file)
      for row in csv_reader:
         pilot = row['CHANNEL']
         lap_time = datetime.datetime.strptime(row['TIME'], '%M:%S.%f').time()
         lap_time_ms = ((lap_time.hour * 60 + lap_time.minute) * 60 + lap_time.second) * 1000 + int(lap_time.microsecond / 1000)
         data.setdefault(pilot, {}).setdefault('Laps', []).append(lap_time)
         data[pilot].setdefault('LapMs', []).append(lap_time_ms)
         data[pilot].setdefault('LapS', []).append(lap_time_ms/1000)
         #data[pilot].setdefault('Title', '')
         data[pilot]['Title'] = "%s (%s)" % (row['PILOT'], row['CHANNEL'])

   return data


def calculate_statistics(data):
   for pilot, pilot_data in data.items():
      count = 0
      best3 = 0.0
      pilot_data['Best3'] = []
      pilot_data['MinTime'] = []
      pilot_data['Min3Time'] = []
      pilot_data['Min3Lap'] = []
      min_time = None
      min3_time = None
      for idx, filtered in enumerate(pilot_data.get('Filtered', [])):
         if not filtered:
            best3 = 0
            count = 0
            continue
         lap_time = pilot_data['LapS'][idx]
         min_time = min(min_time if min_time is not None else lap_time, lap_time)
         pilot_data['MinTime'].append(min_time)
         count += 1
         best3 += lap_time
         if count == 3:
            pilot_data['Best3'].append(best3)
            min3_time = min(min3_time if min3_time is not None else best3, best3)
            pilot_data['Min3Time'].append(min3_time)
            pilot_data['Min3Lap'].append(len(pilot_data['MinTime']))
            count = 0
            best3 = 0.0

   return None


def filter_data(data, min_lap_time = 5.0, max_lap_time=60.0, pilot=None):
   if pilot is not None:
      data = {pilot: data[pilot]}
   for pilot, pilot_data in data.items():
      laps = np.array(pilot_data['LapS'])
      pilot_data['Filtered'] = np.logical_and(laps >= min_lap_time, laps <= max_lap_time)
      #print(pilot_data['Filtered'])

   return data


def plot(chart_path, data, statistics, bounds, bin_width=1.0, max_lap_time=60.0):
   hist_data = []
   names = []
   fig, axs = plt.subplots(len(data), 2, squeeze=False, figsize=(16, 12))
   
   #fig.set_size_inches(10, 16)
   
   plot = 0
   colors = ['blue', 'red', 'green', 'yellow', 'purple']
   ymax = [0, 0]
   ymin = [0, 999999999]
   xmax = 0
   #for pilot, pilot_data in data.items():
   for pilot in sorted(data.keys()):
      pilot_data = data[pilot]
      
      #print(pilot_data['Best3'])

      n, bins, pathces = axs[plot, 0].hist(
         [pilot_data['LapS'], np.array(pilot_data['Best3']) / 3.0],
         bins=np.concatenate(([0.0], np.arange(bounds[0], bounds[1], bin_width), [max_lap_time])),
         histtype='stepfilled',
         alpha=0.7,
         label=['1lap', '3lap average']
      )
      ymax[0] = max(ymax[0], np.max(n))
      axs[plot, 0].set_title(pilot_data['Title'])
      axs[plot, 0].grid(True, which='both')
      axs[plot, 0].set_xticks(range(int(bounds[0]), int(bounds[1]), 2))
      axs[plot, 0].set_xlim([bounds[0] - 1, bounds[1] + 1])
      axs[plot, 0].set_ylabel('Count')
      axs[plot, 0].set_xlabel('Lap Time [s]')

      axs[plot, 0].legend()
      xmax = max(xmax, len(pilot_data['MinTime']))
      min3_average = np.array(pilot_data['Min3Time']) / 3.0
      ymax[1] = max(ymax[1], max(pilot_data['MinTime']), max(min3_average))
      ymin[1] = min(ymin[1], min(pilot_data['MinTime']), min(min3_average))
      axs[plot, 1].plot(range(1, len(pilot_data['MinTime']) + 1), pilot_data['MinTime'], label='min_time')
      axs[plot, 1].plot(pilot_data['Min3Lap'], min3_average, label='min3_average')
      axs[plot, 1].grid(True, which='both')
      axs[plot, 1].minorticks_on()
      axs[plot, 1].set_ylabel('Lap Time [s]')
      axs[plot, 1].set_xlabel('Laps')
      axs[plot, 1].set_yticks(np.arange(int(ymin[1] - 2), ymax[1] + 1, 2.0))
      axs[plot, 1].legend()
      plot += 1

   #print(ymax)
   for a in axs:
      a[0].set_ylim([0, ymax[0]])
      a[1].set_xlim([0, xmax])
      a[1].set_ylim([ymin[1] - 1, ymax[1] + 1])

   plt.tight_layout()
   if chart_path:
      plt.savefig(chart_path, format='png', dpi=200)
   else: 
      plt.show()


def main():
   parser = argparse.ArgumentParser()
   parser.add_argument('--csv')
   parser.add_argument('--chart')
   parser.add_argument('--hist-left-bound', type=float, required=True)
   parser.add_argument('--hist-right-bound', type=float, required=True)
   parser.add_argument('--only-pilot')
   args = parser.parse_args()

   data = read_data(args.csv)
   filtered_data = filter_data(data, pilot=args.only_pilot)
   statistics = calculate_statistics(filtered_data)
   hist_bounds = [args.hist_left_bound, args.hist_right_bound]
   plot(args.chart, filtered_data, statistics, bounds=hist_bounds)


if __name__ == "__main__":
   main()


