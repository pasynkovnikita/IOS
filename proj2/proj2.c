/*
 * Nikita Pasynkov, xpasyn00@stud.fit.vutbr.cz
 */


#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
#include <semaphore.h>
#include <sys/mman.h>
#include <sys/types.h> //pid_t
#include <sys/wait.h> //waitpid
#include <sys/ipc.h>
#include <sys/shm.h>

long int    NO, // number of oxygens
            NH, // number of hydrogens
            TI, // max time before going to queue
            TB; // max time fore creating a molecule

int *counter = 0,        // counter of events
    *hydrogen_count = 0, // counter of hydrogens
    *oxygen_count = 0, // counter of oxygens
    *atoms_in_bond = 0,
    *molecule_count = 0;

sem_t *sem_oxygen,      // semaphore for oxygen bonding
      *sem_hydrogen,    // semaphore for hydrogen bonding
      *crit_sec_wait,   // for going into critical section
      *sem_write,       // for writing events into and output file
      *sem_bonding,     // for waiting 3 atoms in bonding
      *sem_bond_finish, // for finishing bonding
      *sem_finished,    // for finishing atoms
      *sem_block;       // for critical section in bonding

FILE *output = NULL;    // output file

#define wait_for_bond_finish(atoms) do{\
                sem_wait(sem_block);\
                (*atoms_in_bond)++;\
                if (*atoms_in_bond == 3){\
                (*molecule_count)++;\
                if(*molecule_count == atoms )\
                    sem_post(sem_finished);\
                    (*atoms_in_bond) = 0;\
                    sem_post(sem_bond_finish);\
                    sem_post(sem_bond_finish);\
                    sem_post(sem_bond_finish);\
                }\
                sem_post(sem_block);}\
                while (0)

int parse_args (char *argv[]) { // parse the command line arguments, returns 0 if successful
    char *endptr;

    NO = strtol(argv[1], &endptr, 10);
    if (*endptr != '\0' || NO <= 0) {
        fprintf(stderr, "%s", "Wrong input\n");
        return 1;
    }

    NH = strtol(argv[2], &endptr, 10);
    if (*endptr != '\0' || NH <= 0) {
        fprintf(stderr, "%s", "Wrong input\n");
        return 1;
    }

    TI = strtol(argv[3], &endptr, 10);
    if (*endptr != '\0' || TI < 0 || TI > 1000) {
        fprintf(stderr, "%s", "Wrong input\n");
        return 1;
    }

    TB = strtol(argv[4], &endptr, 10);
    if (*endptr != '\0' || TB < 0 || TB > 1000) {
        fprintf(stderr, "%s", "Wrong input\n");
        return 1;
    }



    return 0;
}

void init(void) {    // initialize semaphores
    // semaphores mmap, init

    sem_oxygen = mmap(NULL, sizeof(sem_t), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    sem_hydrogen = mmap(NULL, sizeof(sem_t), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    sem_bonding = mmap(NULL, sizeof(sem_t), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);  
    sem_write = mmap(NULL, sizeof(sem_t), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    crit_sec_wait = mmap(NULL, sizeof(sem_t), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    sem_block = mmap(NULL, sizeof(sem_t), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    sem_finished = mmap(NULL, sizeof(sem_t), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    sem_bond_finish = mmap(NULL, sizeof(sem_t), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    
    sem_init(sem_oxygen, 1, 0);
    sem_init(sem_hydrogen, 1, 0);
    sem_init(sem_bonding, 1, 1);
    sem_init(sem_write, 1, 1);
    sem_init(crit_sec_wait, 1, 1);
    sem_init(sem_block, 1, 1);
    sem_init(sem_finished, 1, 0);
    sem_init(sem_bond_finish, 1, 0);

    // variables mmap
    counter = mmap(NULL, sizeof(int), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    molecule_count = mmap(NULL, sizeof(int), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    hydrogen_count = mmap(NULL, sizeof(int), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    oxygen_count = mmap(NULL, sizeof(int), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
    atoms_in_bond = mmap(NULL, sizeof(int), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, 0, 0);
}

void write_file(char atom, int i, char *event) {    // writing output into a file
    sem_wait(sem_write);
    fprintf(output, "%d: %c %d: %s\n", ++(*counter), atom, i, event);
    fflush(output);
    sem_post(sem_write);
}

void write_creating_molecule(char atom, int i) {    // writing output for creating a molecule because it's easier
    sem_wait(sem_write);
    fprintf(output, "%d: %c %d: %s %d\n", ++(*counter), atom, i, "creating molecule ", (*molecule_count)+1);
    fflush(output);
    sem_post(sem_write);
}

void write_molecule_created(char atom, int i) {     // writing output for molecule created
    sem_wait(sem_write);
    fprintf(output, "%d: %c %d: molecule %d created\n", ++(*counter), atom, i, (*molecule_count)+1);
    fflush(output);
    sem_post(sem_write);
}

void bonding(char atom, int i, int TB) {    // bonding process
    sem_wait(sem_block);
    if (*atoms_in_bond == 0)
        sem_wait(sem_bonding);
    int delay = 0;
    if (TB != 0)
        delay = (rand() % TB) * 1000;
    usleep(delay);
    (*atoms_in_bond)++;
        write_creating_molecule(atom, i);
    if (*atoms_in_bond == 3){
        (*atoms_in_bond) = 0;
        sem_post(sem_block);
        sem_post(sem_bonding);
        sem_post(sem_bonding);
        sem_post(sem_bonding);
        sem_post(sem_bonding);
        return;
    }
    sem_post(sem_block);

}

void create_o(int NO, int TI, int TB) {     // oxygen atom
    pid_t pid;
    pid_t *children = malloc(NO*sizeof(pid_t));

    int delay = 0;
    for (int i = 1; i <= NO; i++) {
        write_file('O', i, "started");
        if (TI) {
            srand(getpid());    // seed random number generator
            delay = ((rand() % TI) * 1000);
        }
        usleep(delay);

        pid = fork(); 
        if (pid == 0) {
            write_file('O', i, "going to queue");
            sem_wait(crit_sec_wait);
            if (*hydrogen_count >= 2) { //begin bonding process
                sem_post(sem_hydrogen);
                sem_post(sem_hydrogen);
                bonding('O', i, TB);

                sem_wait(sem_bonding);
                write_molecule_created('O', i);

                wait_for_bond_finish(NO);
                sem_wait(sem_bond_finish);
                sem_post(crit_sec_wait);
            }
            else {
                (*oxygen_count)++;
                sem_post(crit_sec_wait);
                sem_wait(sem_oxygen);
                bonding('O', i, TB);               
                sem_wait(sem_bonding);
                write_molecule_created('O', i);
                wait_for_bond_finish(NO);
                sem_wait(sem_bond_finish);
            }

            sem_wait(sem_finished);
            sem_post(sem_bond_finish);
            sem_post(sem_finished);

            exit(0);
        }
        else if (pid > 0) {
            children[i-1] = pid;
        }
    }
    for (int i = 0; i < NO; i++) {
        waitpid(children[i], NULL, 0);
    }
    
    free(children);
    exit(0);
}

void create_h(int NO, int TI, int TB) {     // hydrogen atom
    pid_t pid;
    pid_t *children = malloc(NO*sizeof(pid_t));

    int delay = 0;
    for (int i = 1; i <= NO; i++) {
        write_file('H', i, "started");
        if (TI) {
            srand(getpid());    // seed random number generator
            delay = ((rand() % TI) * 1000);
        }
        usleep(delay);

        pid = fork();
        if (pid == 0) {
            write_file('H', i, "going to queue");
            sem_wait(crit_sec_wait);
            if (*hydrogen_count >= 1 && *oxygen_count > 0) { //begin bonding process
                (*hydrogen_count)--;
                (*oxygen_count)--;
                sem_post(sem_hydrogen);
                sem_post(sem_oxygen);
                bonding('H', i, TB);
                sem_wait(sem_bonding);
                write_molecule_created('H', i);
                wait_for_bond_finish(NH/2);
                sem_wait(sem_bond_finish);
                sem_post(crit_sec_wait);
            }
            else {
                (*hydrogen_count)++;
                sem_post(crit_sec_wait);
                sem_wait(sem_hydrogen);
                bonding('H', i, TB);
                sem_wait(sem_bonding);
                write_molecule_created('H', i);
                wait_for_bond_finish(NH/2);
                sem_wait(sem_bond_finish);
            }
            sem_wait(sem_finished);
            sem_post(sem_bond_finish);
            sem_post(sem_finished);
            exit(0);
        }
        else if (pid > 0) {
            children[i-1] = pid;
        }
    }
    for (int i = 0; i < NO; i++) {
        waitpid(children[i], NULL, 0);
    }
    free(children);
    exit(0);
}

void free_semaphores(void) {
    sem_destroy(sem_oxygen);
    sem_destroy(sem_hydrogen);
    sem_destroy(crit_sec_wait);
    sem_destroy(sem_bonding);
    sem_destroy(sem_block);
    sem_destroy(sem_finished);
    sem_destroy(sem_bond_finish);

    munmap(sem_oxygen,sizeof(sem_t));
    munmap(sem_hydrogen,sizeof(sem_t));
    munmap(crit_sec_wait,sizeof(sem_t));
    munmap(sem_bonding,sizeof(sem_t));
    munmap(sem_block,sizeof(sem_t));
    munmap(sem_finished,sizeof(sem_t));
    munmap(sem_bond_finish,sizeof(sem_t));
    munmap(oxygen_count,sizeof(int));
    munmap(hydrogen_count,sizeof(int));
    munmap(counter,sizeof(int));
    munmap(molecule_count,sizeof(int));
    munmap(atoms_in_bond,sizeof(int));
}

int main(int argc, char *argv[]) {
    pid_t oxygen, hydrogen = 0;

    init();

    if (argc != 5) {
        fprintf(stderr, "%s", "Wrong number of arguments\n");
        return 1;
    }

    if (parse_args(argv) == 1) {
        return 1;
    }

    output = fopen("proj2.out", "w");

    oxygen = fork();
    if (oxygen == 0) {  // child process - oxygen
        create_o(NO, TI, TB);
    }
    else if (oxygen > 0) {
        hydrogen = fork();
        if (hydrogen == 0) {    // child process - hydrogen
            create_h(NH, TI, TB);
        }
    }
    free_semaphores();
    return 0;
}